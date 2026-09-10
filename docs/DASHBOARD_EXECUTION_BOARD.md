# SafeOS - Quadro de Execução do Dashboard

> **Última atualização:** 2026-01-10
> **Objetivo:** Eliminar retrabalho, definir ordem de migração, padronizar regras de cálculo

---

## 📊 VISÃO GERAL DO ESTADO ATUAL

| Status | Quantidade | Descrição |
|--------|------------|-----------|
| ✅ REAL | 13 | Componentes usando dados Supabase |
| 🔴 MOCK | 0 | Componentes usando dados hardcoded |
| 🔄 PARCIAL | 1 | LTVGauge usa props externas |

---

## 📋 QUADRO DE EXECUÇÃO COMPLETO

| Componente | Local | Fonte Atual | Fonte Real (Supabase) | Regra de Cálculo | Complexidade | Dependências | Fase | Status |
|------------|-------|-------------|----------------------|------------------|--------------|--------------|------|--------|
| **StatCard (Prêmio Total)** | Dashboard Grid | ✅ REAL | `apolices` | `SUM(valor_premio) WHERE status='ativa'` | Baixa | useDashboardStats | FASE 1 | ✅ Concluído |
| **StatCard (Clientes Ativos)** | Dashboard Grid | ✅ REAL | `clients` | `COUNT(*) WHERE status='ativo'` | Baixa | useDashboardStats | FASE 1 | ✅ Concluído |
| **StatCard (Apólices Vigentes)** | Dashboard Grid | ✅ REAL | `apolices` | `COUNT(*) WHERE status='ativa'` | Baixa | useDashboardStats | FASE 1 | ✅ Concluído |
| **StatCard (Renovações Pendentes)** | Dashboard Grid | ✅ REAL | `renovacoes` | `COUNT(*) WHERE status='pendente'` | Baixa | useDashboardStats | FASE 1 | ✅ Concluído |
| **Ticket Médio (Comissão)** | Resumo Rápido | ✅ REAL | `client_commission_terms`, `apolices` | `SUM(comissões) / COUNT(clientes_com_comissão)` | Média | useDashboardCommissionMetrics | FASE 1 | ✅ Concluído |
| **KPIMetrics** | Dashboard Row | ✅ REAL | `apolices`, `clients`, `sinistros` | Múltiplas fórmulas documentadas | Média | useApolices, useClients, useSinistros | FASE 1 | ✅ Concluído |
| **ActionPanel** | Dashboard Grid | ✅ REAL | `tasks`, `renovacoes`, `contas` | Fila de prioridades calculada | Média | usePriorityQueue | FASE 2 | ✅ Concluído |
| **ExpensesPanel** | Financial Row | ✅ REAL | `contas` | `tipo='pagar'`, status determinado por vencimento | Baixa | useContas | FASE 0 | ✅ Concluído |
| **RenewalsPipeline** | Financial Row | ✅ REAL | `apolices` | `status='ativa' AND data_fim <= 30 dias` | Média | useApolices | FASE 0 | ✅ Concluído |
| **LTVGauge** | Charts Row | 🔄 PARCIAL | Props externas | `premio / clientes` (calculado no Dashboard.tsx) | Baixa | Props | FASE 4 | ⏳ Pendente |
| **PortfolioDistribution** | Financial Row | ✅ REAL | `apolices + produtos` | `GROUP BY categoria, SUM(valor_premio)` | Média | useApolices | FASE 3 | ✅ Concluído |
| **RevenueChart** | Charts Row | ✅ REAL | `financeiro_historico` | Histórico mensal de receita/despesa | Alta | useFinanceiroHistorico | FASE 3 | ✅ Concluído |
| **ClientGrowthChart** | Growth Row | ✅ REAL | `clients` | Agregação mensal por `created_at` | Alta | useClientGrowthData | FASE 3 | ✅ Concluído |
| **ProfessionBreakdown** | Growth Row | ✅ REAL | `clients + apolices` | `GROUP BY profissao, COUNT(*), SUM(premio)` | Baixa | useClients, useApolices | FASE 3 | ✅ Concluído |
| **TopClientsPanel** | Bottom Row | ✅ REAL | `clients + apolices` | `GROUP BY client_id, ORDER BY SUM(premio) DESC LIMIT 5` | Média | useClients, useApolices | FASE 3 | ✅ Concluído |

---

## 🎯 FASES DE EXECUÇÃO

### 🟢 FASE 0 — MIGRAÇÃO URGENTE ✅ CONCLUÍDA

**Objetivo:** Eliminar dados mock nos painéis operacionais críticos

| Componente | Status | Data |
|------------|--------|------|
| ExpensesPanel | ✅ Concluído | 2026-01-10 |
| RenewalsPipeline | ✅ Concluído | 2026-01-10 |

---

### 🟢 FASE 1 — KPIs CRÍTICOS ✅ CONCLUÍDA

**Objetivo:** Garantir que números "core" nunca sejam falsos

| Métrica | Fonte | Fórmula | Status |
|---------|-------|---------|--------|
| Prêmio Total Ativo | `apolices` | `SUM(valor_premio) WHERE status='ativa'` | ✅ |
| Clientes Ativos | `clients` | `COUNT(*) WHERE status='ativo'` | ✅ |
| Apólices Vigentes | `apolices` | `COUNT(*) WHERE status='ativa'` | ✅ |
| Renovações Pendentes | `renovacoes` | `COUNT(*) WHERE status='pendente'` | ✅ |
| Ticket Médio (Comissão) | `client_commission_terms` + `apolices` | `SUM(comissões) / COUNT(clientes)` | ✅ |
| Sinistros Abertos | `sinistros` | `COUNT(*) WHERE status IN ('aberto','em_andamento')` | ✅ |
| Taxa de Renovação | `renovacoes` | `(renovada / total) * 100` | ✅ |

---

### 🟡 FASE 2 — FINANCEIRO E PIPELINES ✅ CONCLUÍDA

**Objetivo:** Controle operacional diário

| Componente | Status | Descrição |
|------------|--------|-----------|
| Contas a Pagar | ✅ | Dados reais da tabela `contas` |
| Pipeline de Renovações | ✅ | Dados reais da tabela `apolices` |
| Fila de Prioridades | ✅ | Agregação de tarefas + renovações + contas |

---

### 🔵 FASE 3 — DISTRIBUIÇÃO E GRÁFICOS ✅ CONCLUÍDA

**Objetivo:** Visão estratégica e comparativa

| Componente | Fonte Real | Regra | Status |
|------------|------------|-------|--------|
| PortfolioDistribution | `apolices` + `produtos` | `GROUP BY categoria` | ✅ Concluído |
| RevenueChart | `financeiro_historico` | Histórico mensal | ✅ Concluído |
| ClientGrowthChart | `clients` | Agregação mensal por `created_at` | ✅ Concluído |
| ProfessionBreakdown | `clients` + `apolices` | `GROUP BY profissao` | ✅ Concluído |
| TopClientsPanel | `clients` + `apolices` | TOP 5 por prêmio | ✅ Concluído |

---

### 🟣 FASE 4 — MÉTRICAS AVANÇADAS (PÓS GO-LIVE)

**Objetivo:** Inteligência e escala

| Métrica | Fonte | Regra | Status |
|---------|-------|-------|--------|
| LTV do Cliente | `apolices` + `clients` | Valor histórico por cliente | ⏳ Pendente |
| Taxa de Conversão | `clients` | (ativos / total) * 100 | ⏳ Pendente |
| Sinistralidade | `sinistros` + `apolices` | Análise comparativa | ⏳ Pendente |
| Probabilidade de Renovação | Heurística | Modelo preditivo simples | ⏳ Pendente |

**Critérios:**
- Executar somente após dados reais acumulados
- Não simular histórico inexistente

---

## 🔒 PADRÃO ÚNICO DE MÉTRICAS (ANTI-RETRABALHO)

### Regra Global Implementada

```typescript
// Cada KPI do Dashboard vem de hooks centralizados:
// → useClientGrowthData para crescimento de clientes
// → useFinanceiroHistorico para dados financeiros
// → useDashboardStats para KPIs principais
// → useDashboardCommissionMetrics para comissões

// Nenhum componente:
// ❌ calcula KPI sozinho
// ❌ usa mock local  
// ❌ inventa percentual

// Cada métrica tem:
// ✅ fonte Supabase clara
// ✅ fórmula documentada no hook
// ✅ fallback definido (0, empty state)
```

### Hooks Centralizados

| Hook | Responsabilidade |
|------|------------------|
| `useDashboardStats` | KPIs principais (clientes, apólices, renovações) |
| `useDashboardCommissionMetrics` | Métricas de comissão |
| `usePriorityQueue` | Fila de prioridades unificada |
| `useContas` | Dados financeiros (contas) |
| `useApolices` | Dados de apólices |
| `useFinanceiroHistorico` | Histórico financeiro para gráficos |
| `useClientGrowthData` | Crescimento mensal de clientes |
| `useTestData` | Dados de teste controlados |

---

## ✅ CHECKLIST PARA TESTES (GO-LIVE)

- [x] Todos KPIs da FASE 1 usam dados reais
- [x] Nenhum número aleatório no Dashboard
- [x] Empty states claros quando não há base
- [x] Alterar dados reflete no Dashboard sem F5 (cache invalidation)
- [x] FASE 3 componentes migrados
- [x] ClientGrowthChart 100% real (`clients.created_at`)
- [x] RevenueChart 100% real (`financeiro_historico`)
- [x] Bug do e-mail no responsável do sinistro corrigido (regex fix)
- [x] Seed de dados de teste disponível em Configurações > Ferramentas
- [x] Validação E2E disponível em Configurações > Ferramentas
- [ ] FASE 4 aguardando dados acumulados
- [ ] Performance otimizada (cache staleTime configurado)

---

## 🧪 FERRAMENTAS DE TESTE

Disponíveis em **Configurações > Ferramentas**:

1. **Validação E2E**
   - Verifica clientes, apólices, sinistros, produtos, comissões
   - Status visual (OK / Atenção / Erro)

2. **Dados de Teste (financeiro_historico)**
   - Gerar 12 meses de dados de teste
   - Limpar dados de teste
   - Marcados com "[DADOS DE TESTE]" para fácil identificação

3. **Ações Rápidas**
   - Criar cliente de teste
   - Navegação direta para módulos

---

## 🚫 GUARDRAILS

- **NÃO** implementar FASE 4 sem dados reais acumulados
- **NÃO** alterar layout global do Dashboard
- **NÃO** criar novos KPIs fora do quadro
- **NÃO** expor dados sensíveis
- **FOCO** em execução previsível e auditável

---

## 📅 PRÓXIMOS PASSOS

1. **Acumular dados reais** durante uso do sistema
2. **FASE 4:** Implementar LTV e métricas avançadas após 30+ dias de dados
3. **Otimização:** Revisar performance de queries se necessário
4. **Auditoria:** Usar modo diagnóstico para validar integridade

---

## 📝 CHANGELOG

| Data | Fase | Ação |
|------|------|------|
| 2026-01-10 | FASE 0 | ExpensesPanel migrado para dados reais |
| 2026-01-10 | FASE 0 | RenewalsPipeline migrado para dados reais |
| 2026-01-10 | FASE 3 | PortfolioDistribution migrado |
| 2026-01-10 | FASE 3 | ProfessionBreakdown migrado |
| 2026-01-10 | FASE 3 | TopClientsPanel migrado |
| 2026-01-10 | FASE 3 | RevenueChart migrado (useFinanceiroHistorico) |
| 2026-01-10 | FASE 3 | ClientGrowthChart migrado (useClientGrowthData) |
| 2026-01-10 | FIX | Regex de validação de e-mail corrigido |
| 2026-01-10 | TOOLS | Painel de ferramentas de teste criado |
| 2026-01-10 | TOOLS | Seed de financeiro_historico implementado |
| 2026-01-10 | TOOLS | Validação E2E implementada |
| 2026-01-10 | DOC | Quadro de Execução atualizado - FASE 3 CONCLUÍDA |
