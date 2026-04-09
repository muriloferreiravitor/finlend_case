# Glossário de Negócio · FinLend

Referência dos termos de domínio financeiro utilizados no projeto. Voltado a leitores com perfil técnico que precisam de contexto sobre o modelo de negócio.

## Modelo de Negócio

**Correspondente Bancário:** empresa autorizada pelo BACEN (Resolução CMN 4.935/21) a intermediar operações financeiras em nome de instituições parceiras. A FinLend não é um banco e não assume risco de crédito; conecta as partes e cobra comissão.

**Personal Banker (merchant no código):** bancário autônomo que utiliza a plataforma para distribuir produtos financeiros de múltiplos parceiros. No código, corresponde a `merchant_id` / `merchant_name`.

**Marketplace financeiro:** a FinLend integra 50+ instituições com 150+ produtos. O Personal Banker compara ofertas e indica a mais adequada ao cliente.

## Fluxo Financeiro

Para cada transação intermediada, três valores coexistem:

| Conceito | Campo (fct_revenue) | Campo (merchant_summary) | Significado |
|----------|---------------------|--------------------------|-------------|
| **GMV** (volume bruto) | `gmv_impact` | `total_gmv` | Valor total da operação do cliente. Não é receita da FinLend. |
| **Fee** (receita FinLend) | `finlend_revenue_impact` | `total_finlend_revenue` | Comissão retida pela plataforma. Este é o faturamento da empresa. |
| **Net** (líquido do merchant) | `merchant_net_impact` | `total_merchant_net` | Valor repassado ao Personal Banker (amount - fee). |

**Take Rate:** razão entre fees e GMV. Indica a capacidade de monetização da plataforma. Exemplo: take rate de 1% significa que a FinLend retém R$ 1 para cada R$ 100 transacionados.

## Liquidação (Settlement)

**Settlement:** efetivação financeira em lote. Enquanto a transação é o evento ("cliente contratou seguro"), o settlement é o pagamento ("banco pagou a comissão à FinLend"). Cada settlement agrupa múltiplas transações em um único pagamento, por isso `transaction_ids` é um array na source.

**D+N:** prazo de liquidação. D+0 = mesmo dia; D+2 = dois dias úteis. Cada parceiro e produto tem prazo distinto, o que justifica o lookback de 3 dias no modelo incremental.

**Reconciliação:** verificação de que os valores internos coincidem com os dos parceiros. Erros de truncamento (como divisão inteira) impossibilitam esse processo.

## Status de Transação

| Status | Significado | Entra no fct_revenue? |
|--------|-------------|:---------------------:|
| `captured` | Operação efetivada com sucesso | Sim |
| `refunded` | Estorno voluntário | Sim (valor negativo) |
| `chargeback` | Reversão por contestação formal | Sim (valor negativo) |
| `pending` | Aguardando processamento | Não |
| `authorized` | Autorizada, não capturada | Não |
| `cancelled` | Cancelada antes da efetivação | Não |
| `test` e variações | Transações de homologação | Filtrado no staging via seed |

## Risco e Compliance

**Chargeback Rate:** proporção de chargebacks sobre o total de transações. Thresholds da indústria: < 0,5% saudável, > 1% alerta, > 2% crítico. As bandeiras Visa (VDMP) e Mastercard (ECM) aplicam multas progressivas acima desses limites.

**MCC Code:** código de 4 dígitos que classifica o segmento de atuação do merchant.

## Métricas de Startup

**Unit Economics:** rentabilidade por unidade de negócio (por Personal Banker ou por transação). Depende de dados corretos de receita, fee e volume.

**Due Diligence:** auditoria de investidores antes de aportar capital. Inclui verificação de métricas financeiras e qualidade de dados.