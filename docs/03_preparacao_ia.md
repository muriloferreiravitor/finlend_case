# Parte 3 · Preparação para IA

## Objetivo

Preparar os modelos refatorados para consumo por um agente de IA capaz de responder perguntas de negócio em linguagem natural, gerando SQL contra o data warehouse.

## Entregáveis

| Arquivo | Função |
|---------|--------|
| `models/marts/_marts_models.yml` | Meta tags semânticas, descrições e testes nos modelos marts |
| `SEMANTIC_NOTES.md` | Guia de roteamento, exemplos de SQL, armadilhas e lacunas |

## Estratégia de Meta Tags

Foi definido um vocabulário controlado de meta tags, parseável tanto por humanos quanto por LLMs:

| Tag | Valores | Função |
|-----|---------|--------|
| `semantic_type` | metric, dimension, identifier, timestamp, flag | Classificação da coluna para o LLM saber se pode somar, filtrar ou agrupar |
| `unit` | BRL, count, ratio, days | Unidade de medida; evita erros como tratar ratio (0-1) como percentual (0-100) |
| `business_alias` | lista de strings | Termos de linguagem natural que mapeiam ao campo (ex: "receita" -> finlend_revenue_impact) |
| `warning` | texto livre | Instrução imperativa para o LLM (ex: "NÃO usar para receita") |
| `example_questions` | lista de strings | Perguntas que o modelo responde; auxilia no roteamento |
| `grain` | texto | O que cada linha representa; essencial para o LLM saber se precisa agregar |

## Defesas Contra Erros do Agente

As seis armadilhas documentadas no `SEMANTIC_NOTES.md` e as meta tags que as previnem:

| Armadilha | Risco | Defesa |
|-----------|-------|--------|
| Confundir GMV com receita | Erro de 50-200x no valor reportado | `warning` em gmv_impact; `business_alias` em finlend_revenue_impact |
| Usar merchant_summary para período específico | Retorno de métricas all-time em vez do período solicitado | `warning` no nível do modelo |
| Payment method case-sensitive | Query sem resultados | Descrição com valor exato (`'pix'`) |
| Tratar ratio como percentual | Filtro ineficaz (>2 ao invés de >0.02) | `unit: ratio` + filtro explícito na descrição |
| JOINs desnecessários | Custo e complexidade evitáveis | Descrições com "já pré-agregado" |
| NULLs de settlement | Receita subestimada | finlend_revenue_impact com COALESCE + flag is_pending_settlement |

## Lacunas Identificadas

Documentadas na seção 4 do `SEMANTIC_NOTES.md`. As três mais relevantes:

1. **dbt Semantic Layer / MetricFlow**: permitiria ao agente consultar métricas por API ao invés de gerar SQL. Eliminaria a maioria das armadilhas de geração.

2. **Dimensões inexistentes**: não há modelo de parceiro financeiro nem de tipo de produto. Perguntas como "volume pelo parceiro X" ou "financiamentos imobiliários" são irrespondíveis com a modelagem atual.

3. **Modelos temporais intermediários**: perguntas com período exigem scan do fct_revenue (milhões de linhas). Um `merchant_monthly_metrics` intermediário reduziria custo e complexidade do SQL gerado.