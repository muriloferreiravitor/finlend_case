# Parte 1 · Diagnóstico do Projeto Legado

## Critérios de Priorização

1. **Correção financeira:** os números de receita e fees estão errados?
2. **Risco regulatório:** pode causar problemas com BACEN ou bandeiras de cartão?
3. **Custo operacional:** contribui para o aumento da conta do BigQuery?
4. **Escalabilidade:** o problema se agrava com o crescimento da base?
5. **Viabilidade do agente de IA:** bloqueia ou prejudica a geração de SQL por LLM?

Severidade: 🔴 Crítico · 🟡 Alto · 🟠 Médio · ⚪ Baixo

---

## 🔴 P1 · Divisão inteira corrompe toda a camada financeira

**Arquivo:** `stg_transactions.sql`
**Trecho:** `amount_cents / 100 as amount_brl`

No BigQuery, `INT64 / INT64` retorna `INT64` com truncamento. Transação de 1999 centavos resulta em R$ 19 ao invés de R$ 19,99. Esse erro se propaga para `revenue_report.revenue_impact` e `merchant_summary.total_revenue`, comprometendo toda a receita reportada.

**Impacto:** receita sistematicamente subreportada, reconciliação com parceiros impossível, base de cálculo fiscal incorreta. Em volume, a diferença acumulada é material.

**Correção:** `ROUND(CAST(amount_cents AS NUMERIC) / 100, 2)`. NUMERIC (precisão 38, escala 9) é o tipo correto para dados financeiros. FLOAT64 introduz erros de ponto flutuante.

---

## 🔴 P2 · JOIN com UNNEST: custo explosivo no BigQuery

**Arquivo:** `revenue_report.sql`
**Trecho:** `ON t.transaction_id IN UNNEST(s.transaction_ids)`

O padrão força full scan em `settlements`, UNNEST em cada linha, e cross-join implícito. A complexidade é O(N × M × K), onde N = transações, M = settlements, K = itens por array. O custo cresce de forma quadrática com o volume.

No modelo de correspondente bancário, settlements são processados em lote (dezenas de transações por lote). Com crescimento da base de Personal Bankers, o custo do JOIN cresce mais rápido que o volume. Este é, com alta probabilidade, o principal fator do aumento de 3x na conta do BigQuery.

**Correção:** criar `stg_settlements` com UNNEST isolado, transformando o JOIN no mart em equi-join por `transaction_id` (complexidade O(N+M)). Redução estimada de 90-95% nessa operação.

---

## 🔴 P3 · Full refresh sem lógica incremental

**Arquivo:** `revenue_report.sql`
**Config:** `materialized='table'`

O modelo recria toda a tabela a cada execução, reprocessando o histórico inteiro incluindo o JOIN do P2. O particionamento por dia existe mas não é aproveitado, pois não há filtro incremental.

**Impacto:** custo cumulativo que cresce linearmente com o histórico. Combinado com P2, o efeito é multiplicativo: o crescimento de 70% no volume gera aumento de ~190% no custo, o que explica quantitativamente a conta triplicada.

**Correção:** `materialized='incremental'` com estratégia merge, `unique_key='transaction_id'`, partição mensal e lookback de 3 dias configurável via `var()`.

---

## 🔴 P4 · Marts acessam sources diretamente

**Arquivo:** `revenue_report.sql`
**Trecho:** `source('raw', 'merchants')` e `source('raw', 'settlements')` referenciados no mart.

Viola a arquitetura `sources → staging → marts`. Sem staging intermediário para merchants e settlements, não existe camada de normalização de tipos, deduplicação, ou testes. Mudanças no schema da source quebram os marts diretamente.

**Impacto:** com 50+ instituições parceiras alimentando dados em formatos variados, a ausência de camada de absorção torna o pipeline frágil. Duplicatas no cadastro de merchants podem multiplicar receita silenciosamente.

**Correção:** criar `stg_merchants.sql` e `stg_settlements.sql`. Marts referenciam exclusivamente `ref()`.

---

## 🟡 P5 · Chargeback rate retorna zero

**Arquivo:** `merchant_summary.sql`
**Trecho:** `SUM(CASE WHEN status = 'chargeback' THEN 1 ELSE 0 END) / COUNT(*)`

Divisão inteira: `INT64 / INT64 = INT64`. Para qualquer merchant com taxa abaixo de 100%, o resultado é 0.

**Impacto:** o time de risco não consegue identificar Personal Bankers problemáticos. Chargebacks acima dos thresholds das bandeiras (Visa VDMP, Mastercard ECM) passam despercebidos, expondo a empresa a multas. A pergunta do case ("merchants com chargeback acima de 2%") sempre retornaria vazio.

**Correção:** `SAFE_DIVIDE()`, que opera em FLOAT64 e retorna NULL quando o divisor é zero.

---

## 🟡 P6 · schema.yml sem testes, freshness ou documentação

O schema.yml contém descrições genéricas ("staging transactions"), nenhum teste (`unique`, `not_null`, `accepted_values`), nenhum source freshness, e nenhuma documentação de coluna.

**Impacto:** problemas nos dados chegam silenciosamente aos dashboards. Sem freshness, a ingestão de um parceiro pode parar por dias sem detecção. Para o agente de IA, a ausência de descrições impede a geração correta de SQL: sem orientação, um LLM usaria `amount_brl` (GMV) ao invés de `fee_amount` (receita) para perguntas sobre faturamento.

**Correção:** implementado nos yml co-localizados (`_sources.yml`, `_stg_models.yml`, `_marts_models.yml`) entre as Partes 2 e 3.

---

## 🟡 P7 · Deduplicação não determinística

**Arquivo:** `revenue_report.sql`
**Trecho:** `ROW_NUMBER() OVER (PARTITION BY transaction_id ORDER BY settlement_date DESC)`

Quando dois settlements têm a mesma data, o ROW_NUMBER escolhe arbitrariamente. Resultados podem variar entre execuções, impossibilitando reconciliação contábil.

Adicionalmente, a existência de duplicatas não é documentada nem monitorada. Não está claro se múltiplos settlements por transação são esperados (ajustes) ou indicam erro na ingestão.

**Correção:** adicionar `settlement_id DESC` como critério de desempate. Documentar a regra de negócio.

---

## 🟠 P8 · revenue_impact mede GMV, não receita da empresa

**Arquivo:** `revenue_report.sql`
**Trecho:** `WHEN status = 'captured' THEN amount_brl ... END as revenue_impact`

O campo `revenue_impact` utiliza `amount_brl` (valor bruto da operação), não `fee_amount` (comissão retida pela plataforma). Em um modelo de marketplace por fees, isso equivale a reportar como receita o volume total transacionado. A diferença pode ser de 50 a 200 vezes, dependendo do take rate.

**Impacto:** o campo se chama "revenue" mas mede GMV. O `merchant_summary.total_revenue` herda essa confusão. O CFO, investidores e o agente de IA obteriam números que não representam o faturamento real.

**Correção:** separar em três métricas explícitas: `gmv_impact`, `finlend_revenue_impact` (fees) e `merchant_net_impact`.

---

## 🟠 P9 · Filtro de status de teste frágil

**Arquivo:** `stg_transactions.sql`
**Trecho:** `WHERE status != 'test'`

Case-sensitive, hardcoded, não auditável. Variações como 'Test', 'testing', 'sandbox' passam pelo filtro. Com 50+ parceiros usando padrões distintos, um filtro único e fixo não escala.

**Correção:** utilizar seed dbt (`seed_test_statuses.csv`). Editável sem tocar em SQL, versionada no Git, auditável.

---

## 🟠 P10 · CURRENT_TIMESTAMP() quebra idempotência

**Arquivo:** `stg_transactions.sql`
**Trecho:** `CURRENT_TIMESTAMP() as loaded_at`

O campo muda a cada execução, invalidando o results cache do BigQuery e impedindo idempotência do modelo.

**Correção:** remover o campo. Staging não deve introduzir dados que variam entre execuções. Se necessário, utilizar o timestamp de ingestão da source (`_loaded_at`).

---

## 🟠 P11 · Campo metadata JSON sem parsing

**Arquivo:** `stg_transactions.sql`

O campo `metadata` é passado como STRING/JSON sem extração de atributos. Informações de negócio (tipo de chave Pix, parcelas, referência do parceiro) ficam inacessíveis para queries analíticas e para o agente de IA.

**Correção:** extrair campos frequentes no staging: `pix_key_type`, `installments`, `partner_reference`. Manter `raw_metadata` para exploração futura.

---

## ⚪ P12 · GROUP BY por posição ordinal

**Arquivo:** `merchant_summary.sql`
**Trecho:** `GROUP BY 1, 2, 3`

Agrupamento por posição é frágil: reordenação de colunas no SELECT altera a semântica silenciosamente.

**Correção:** `GROUP BY merchant_id, merchant_name, mcc_code`.

---

## ⚪ P13 · Ausência de meta tags e ownership

Nenhum modelo possui `meta` indicando responsável, domínio, SLA ou classificação de dados. Em uma empresa regulada com dados financeiros, esse é um gap de governança.

**Correção:** implementado no `_marts_models.yml` com meta tags `owner`, `domain`, `sla`, `pii`.

---

## Resumo

| # | Problema | Sev. | Dados | Custo | Regulatório | IA |
|---|----------|:----:|:-----:|:-----:|:-----------:|:--:|
| P1 | Divisão inteira | 🔴 | ✓ | | ✓ | ✓ |
| P2 | UNNEST no JOIN | 🔴 | | ✓✓ | | |
| P3 | Full refresh | 🔴 | | ✓✓ | | |
| P4 | Sources no mart | 🔴 | ✓ | | ✓ | ✓ |
| P5 | Chargeback = 0 | 🟡 | ✓ | | ✓ | ✓ |
| P6 | Schema vazio | 🟡 | ✓ | | ✓ | ✓ |
| P7 | QUALIFY arbitrário | 🟡 | ✓ | | ✓ | |
| P8 | GMV ≠ Receita | 🟠 | ✓ | | | ✓ |
| P9 | Filtro frágil | 🟠 | ✓ | | | |
| P10 | CURRENT_TIMESTAMP | 🟠 | | ✓ | | |
| P11 | Metadata opaco | 🟠 | | | | ✓ |
| P12 | GROUP BY ordinal | ⚪ | | | | |
| P13 | Sem ownership | ⚪ | | | ✓ | ✓ |

## Frentes de Refatoração (detalhes em `docs/02_refatoracao.md`)

| Frente | Problemas | Escopo |
|--------|-----------|--------|
| 1. Staging completo | P1, P2, P4, P9, P10, P11 | stg_transactions, stg_merchants, stg_settlements, _sources.yml, seed |
| 2. fct_revenue | P3, P7, P8 | Incremental, deduplicação determinística, separação GMV/Receita/Net |
| 3. merchant_summary | P5, P12 | SAFE_DIVIDE, métricas de risco, GROUP BY explícito |
| Parte 3 (IA) | P6, P13 | _marts_models.yml enriquecido, SEMANTIC_NOTES.md |