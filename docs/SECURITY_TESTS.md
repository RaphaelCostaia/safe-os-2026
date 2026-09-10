# Testes Automatizados de Segurança e Isolamento RLS

Este documento detalha a suíte de testes de segurança do SafeOS, focada na validação do Row Level Security (RLS) e isolamento Multi-tenant.

## 1. Estrutura de Testes
Os testes estão localizados em `/tests/security/` e utilizam o **Vitest**.

- `rls-isolation.test.ts`: Valida se dados de um tenant vazam para outro.
- `rbac-roles.test.ts`: Valida as permissões específicas de cada papel de usuário.
- `setup.ts`: Utilitários para simular o contexto de autenticação.

## 2. O que está sendo validado
- **Isolamento de Dados**: Garante que `SELECT *` sem filtros nunca retorne dados de outra organização.
- **Prevenção de Bypass**: Testa se a alteração manual de IDs no payload ou na URL é bloqueada pelo banco de dados.
- **Inserção Automática de Tenant**: Verifica se o trigger `fn_set_organization_id` impede que um usuário insira dados em nome de outra empresa.
- **Imutabilidade de Tenant**: Valida que uma vez criado, o `organization_id` de um registro não pode ser alterado, prevenindo sequestro de dados cross-tenant.
- **Privilégios de Role**: Testa se papéis restritos (ex: `leitura`) são impedidos de realizar escritas.

## 3. Como rodar os testes
Para executar a suíte completa de segurança:

```bash
npm run test:security
```

Para rodar em modo assistido (UI):
```bash
npx vitest tests/security --ui
```

## 4. Requisitos de Ambiente
Para que os testes funcionem em ambiente de CI/CD ou localmente, é necessário configurar as seguintes variáveis no `.env`:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (Necessária para o setup de dados fake entre tenants)

## 5. Garantia de RLS
As políticas de segurança foram escritas diretamente no PostgreSQL. Mesmo que o cliente (frontend) seja manipulado para remover filtros, o banco de dados filtrará as linhas antes do retorno do resultado.
