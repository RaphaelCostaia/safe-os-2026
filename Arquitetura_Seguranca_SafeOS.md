# Arquitetura de Segurança e Permissões - SafeOS

Este documento descreve a implementação técnica das camadas de segurança, isolamento de dados e auditoria do sistema SafeOS.

## 1. Visão Geral da Arquitetura
O sistema utiliza uma arquitetura **Multi-tenant SaaS** baseada em discriminador de coluna (`organization_id`). A segurança é aplicada de forma redundante:
1.  **Frontend (UI/UX)**: Botões e rotas são ocultados ou bloqueados via React Hooks (`usePermissions`) e `ProtectedRoute`.
2.  **API/Database (Core)**: Regras de Segurança de Nível de Linha (**RLS Nativo do PostgreSQL**) garantem que nenhum dado seja acessado cross-tenant, mesmo que o frontend seja ignorado.

## 2. Isolamento Multi-tenant
Cada empresa (corretora) é isolada logicamente:
-   **organization_id**: Coluna presente em todas as tabelas sensíveis.
-   **Isolamento de Queries**: O banco injeta automaticamente o filtro `organization_id` baseado no perfil do usuário logado via função stable `public.get_my_org_id()`.
-   **Segurança Cross-Tenant**: É impossível acessar um ID de outra organização, pois o RLS retorna "Not Found" ou "Permission Denied" caso o `organization_id` não coincida.

## 3. Papéis de Usuário (RBAC)
Os papéis são definidos no enum `app_role` e mapeados na tabela `user_roles`.

| Papel | Descrição | Permissão Principal |
| :--- | :--- | :--- |
| **Owner** | Proprietário da Corretora | Acesso total e gerencial. |
| **Admin** | Administrador de Sistema | Configurações, Usuários e Dados. |
| **Gestor** | Gerente de Equipe | Dashboard BI, Produção e Equipe. |
| **Corretor** | Operacional de Vendas | Acessa apenas seus próprios clientes/propostas. |
| **Financeiro** | Gestão de Caixa | Comissões, Contas e Relatórios Financeiros. |
| **Administrativo** | Suporte Interno | Gestão de dados sem acesso à equipe. |
| **Leitura** | Auditores/Consultas | Apenas visualização. |

## 4. Row Level Security (RLS)
Todas as operações de escrita e leitura validam:
-   `auth.uid()` (Identidade)
-   `organization_id` (Isolamento de Empresa)
-   `app_role` (Autorização de Ação)

### Tabelas Protegidas:
- `clients`, `apolices`, `sinistros`, `financeiro_historico`, `contas`, `custos_fixos`, `client_commission_terms`, `client_documents`, `client_notes`, `produtos`.

## 5. Sistema de Auditoria
Implementamos uma trilha de auditoria automatizada via triggers de banco de dados (`audit_logs`):
-   **Eventos**: Rastreia `INSERT`, `UPDATE` e `DELETE`.
-   **Conteúdo**: Mantém snapshot dos `old_data` e `new_data` para cada alteração.
-   **Rastreabilidade**: Registra quem alterou, quando e em qual organização.

## 6. Boas Práticas e Segurança Adicional
-   **API Keys**: A `service_role` nunca é enviada ao navegador. Todas as chamadas são via `anon` key + JWT do usuário.
-   **Prevenção de Injeção**: Uso de Queries Parametrizadas nativas do PostgREST (Supabase).
-   **Backup**: Backup automático diário gerenciado pela infraestrutura Supabase (Spark/Standard Plan).

## 7. Recomendações Futuras
-   **2FA (MFA)**: A estrutura está preparada para autenticação de dois fatores.
-   **Email Whitelisting**: Restrição de domínios para convites.
