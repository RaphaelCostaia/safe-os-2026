# Relatório Técnico de Segurança - SafeOS (Supabase/RLS)

Este relatório detalha as regras técnicas de segurança aplicadas diretamente no Banco de Dados (PostgreSQL) para garantir a integridade e privacidade dos dados.

## 1. Implementação de RLS (Row Level Security)
Diferente de sistemas que dependem apenas de lógica no código (frontend/backend), o SafeOS utiliza **RLS Nativo**. Isso significa que a regra está "escrita no disco" do banco de dados.

- **Políticas de Leitura**: Aplicam filtros automáticos `WHERE organization_id = user_org_id`.
- **Políticas de Escrita**: Validam se o usuário tem permissão (`admin`, `owner`, `gestor`) antes de permitir qualquer modificação.
- **Proteção Cross-Tenant**: Se um atacante tentar acessar o ID de uma apólice de outra corretora via API, o banco retornará zero resultados, pois a linha não pertence à organização dele.

## 2. Trilha de Auditoria (Audit Logs)
A tabela `audit_logs` captura:
- **Ação**: Qual operação foi realizada (INSERT, UPDATE, DELETE).
- **Dados**: Snapshot do JSON antes e depois da alteração (Permite "Undo" ou rastrear quem alterou um valor financeiro).
- **Origem**: IP Address e User Agent do dispositivo que realizou a ação.
- **Metadados**: Timestamp preciso e ID do registro afetado.

## 3. Estrutura de Multi-Tenancy
O sistema foi preparado para rodar no modelo **SaaS (Software as a Service)**:
- Isolamento por `organization_id`.
- Tabela de `organizations` para gerenciar assinaturas e status de cada corretora.
- Função customizada `public.has_any_role` para check de permissões granulares em milissegundos.

## 4. Segurança de Arquivos e Documentos
Documentos anexados (PDFs de apólices, fotos de vistorias) seguem a mesma regra de proteção da tabela `client_documents`, garantindo que apenas usuários autorizados da mesma organização possam visualizar os links de download.

## 5. Resumo de Ambientes
- **Development**: Local de testes e implementações rápidas.
- **Homologação**: Ambiente de espelho para validação do cliente.
- **Produção**: Ambiente altamente seguro com monitoramento de logs 24/7.
