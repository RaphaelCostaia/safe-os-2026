-- =###################################################################################
-- # SISTEMA SAFE-OS (MEDSAFE CORRETORA) - SCRIPT DE LIMPEZA GERAL DE BANCO DE DADOS
-- # OBJETIVO: Preparar o sistema para entrada em PRODUÇÃO REAL.
-- # REGRA DE RETENÇÃO: Mantém APENAS os usuários ADMINS E MASTERS, limpando todo o resto.
-- ####################################################################################
--
-- INSTRUÇÕES DE EXECUÇÃO:
-- 1. Abra o painel do Supabase do projeto de Produção.
-- 2. Vá em "SQL Editor" e crie uma nova query.
-- 3. Cole todo o conteúdo deste arquivo e clique em "Run" (Executar).
-- 4. O script deve ser executado com privilégios de superusuário (padrão do SQL Editor).
--
-- ====================================================================================

BEGIN;

-- 1. CONFIGURAÇÃO DE SEGURANÇA NA SESSÃO (DESATIVAR TRIGGERS E REGRAS DE CONFLITO)
-- Define a sessão como 'replica' para desativar temporariamente todos os Triggers do banco
-- (evitando que inserções de auditoria ou triggers de tenant disparem durante a purgação do banco).
SET session_replication_role = 'replica';

-- 2. MAPEAMENTO DOS USUÁRIOS QUE DEVEM SER SALVOS E PRESERVADOS
-- Criamos uma tabela temporária contendo os IDs e emails que são imutáveis e protegidos.
-- Serão protegidos:
--   a) Os e-mails Masters expressamente definidos no código do Safe-OS.
--   b) Qualquer usuário que possua papel 'admin' ou 'owner' na tabela de roles.
CREATE TEMP TABLE users_to_keep AS
SELECT DISTINCT u.id, LOWER(u.email) as email
FROM auth.users u
LEFT JOIN public.user_roles r ON u.id = r.user_id
WHERE 
  LOWER(u.email) IN ('nexusaionline@gmail.com', 'comercial@medsafecorretora.com.br')
  OR r.role IN ('admin', 'owner');

-- 3. PURGAÇÃO FÍSICA DAS TABELAS DE DADOS (TRANSAÇÕES, CLIENTES, APÓLICES, SINISTROS)
-- Limpa completamente os registros gerados de forma bottom-up (filhos -> pais).

-- A. Históricos, Atividades e Logs Operacionais
-- Limpando logs de auditoria e históricos operacionais...
TRUNCATE TABLE public.activity_log RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.audit_logs RESTART IDENTITY CASCADE;

-- B. Documentos e Anexos Digitais relacionados
-- Limpando anexos e arquivos das tabelas...
TRUNCATE TABLE public.apolice_documents RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.sinistro_documents RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.client_documents RESTART IDENTITY CASCADE;

-- C. Registros e Historiadores de Sinistros
-- Limpando base de sinistros e acompanhamentos...
TRUNCATE TABLE public.sinistro_activities RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.sinistro_notes RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.sinistro_tips RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.sinistros RESTART IDENTITY CASCADE;

-- D. Apólices, Comissões e Renovações
-- Limpando carteira de comercialização de apólices de teste...
TRUNCATE TABLE public.renovacoes RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.contas RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.client_commission_terms RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.apolices RESTART IDENTITY CASCADE;

-- E. Contabilidade Financeira, Metas e Custos Fixos
-- Limpando registros de faturamento financeiro e custos permanentes...
TRUNCATE TABLE public.custos_fixos RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.financeiro_historico RESTART IDENTITY CASCADE;

-- F. CRM, Cadastros de Clientes, Notas do Funil e Interações
-- Limpando carteira de leads, clientes e anotações do funil CRM...
TRUNCATE TABLE public.client_notes RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.clients RESTART IDENTITY CASCADE;

-- G. Projetos, Tarefas Operacionais e Notas Rápidas de Usuários
-- Limpando tarefas e anotações geradas no dia a dia...
TRUNCATE TABLE public.tasks RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.user_notes RESTART IDENTITY CASCADE;
TRUNCATE TABLE public.user_tips RESTART IDENTITY CASCADE;

-- H. Produtos e Coberturas (Limpando para que a corretora cadastre os produtos contratados de fato)
-- Limpando portfólio de produtos configurados...
TRUNCATE TABLE public.produtos RESTART IDENTITY CASCADE;


-- 4. PURGAÇÃO E HIGIENIZAÇÃO DOS USUÁRIOS DO SISTEMA
-- Removemos todos os perfis e acessos que não façam parte da lista de preservação.

-- Removendo usuários de testes e mantendo apenas Administradores/Masters...

-- A. Membros de equipe (Team Members)
DELETE FROM public.team_members
WHERE user_id IS NOT NULL 
  AND user_id NOT IN (SELECT id FROM users_to_keep)
  OR (user_id IS NULL AND LOWER(email) NOT IN (SELECT email FROM users_to_keep));

-- B. Perfis públicos (Profiles) vinculados
DELETE FROM public.profiles
WHERE id NOT IN (SELECT id FROM users_to_keep);

-- C. Papéis atribuídos (User Roles) no escopo multi-tenant
DELETE FROM public.user_roles
WHERE user_id NOT IN (SELECT id FROM users_to_keep);

-- D. Usuários de Autenticação do Supabase (auth.users)
-- (Esta remoção cascateará para tokens de sessão, identidades OAuth do provedor e dados de MFA)
DELETE FROM auth.users
WHERE id NOT IN (SELECT id FROM users_to_keep);


-- 5. TRATAMENTO DE INQUILINOS (ORGANIZATIONS) ÓRFÃOS
-- Se restou alguma organização sem nenhum perfil de administrador/master associado, limpamos do sistema
-- para evitar lixo SaaS acumulado.
-- Limpando organizações órfãs...
DELETE FROM public.organizations o
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p
  WHERE p.organization_id = o.id
);


-- 6. GARANTIR ATRIBUIÇÕES PERFEITAS E HIGIENIZADAS PARA OS USUÁRIOS REMANESCENTES
-- Para garantir que os Mestres estejam com role correta de 'owner', realizamos uma verificação.
DO $$
DECLARE
  v_default_org UUID;
  v_master_id UUID;
  v_emails TEXT[] := ARRAY['nexusaionline@gmail.com', 'comercial@medsafecorretora.com.br'];
  v_email TEXT;
BEGIN
  -- Obtém ID da organização remanescente padrão ou primeira existente
  SELECT id INTO v_default_org FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;
  
  IF v_default_org IS NULL THEN
    SELECT id INTO v_default_org FROM public.organizations LIMIT 1;
  END IF;

  -- Se não existir nenhuma organização (por exemplo, deletou tudo), recria a organização padrão
  IF v_default_org IS NULL THEN
    INSERT INTO public.organizations (name, slug) 
    VALUES ('Organizações MedSafe', 'organizacao-padrao')
    RETURNING id INTO v_default_org;
  END IF;

  -- Garante que o perfil comum de cada master está criado e indexado corretamente
  FOREACH v_email IN ARRAY v_emails
  LOOP
    SELECT id INTO v_master_id FROM auth.users WHERE LOWER(email) = LOWER(v_email);
    
    IF v_master_id IS NOT NULL THEN
      -- Garante o perfil no respectivo tenant
      INSERT INTO public.profiles (id, full_name, email, organization_id, updated_at)
      VALUES (v_master_id, 'MASTER SEGUROS', LOWER(v_email), v_default_org, now())
      ON CONFLICT (id) DO UPDATE 
      SET organization_id = v_default_org, full_name = 'MASTER SEGUROS', updated_at = now();

      -- Garante a role de owner
      INSERT INTO public.user_roles (user_id, role, organization_id)
      VALUES (v_master_id, 'owner'::public.app_role, v_default_org)
      ON CONFLICT (user_id, role) DO UPDATE SET organization_id = EXCLUDED.organization_id;

      -- Garante registro na tabela de membros da equipe (Team Members)
      INSERT INTO public.team_members (user_id, full_name, email, role, is_active, organization_id)
      VALUES (v_master_id, 'MASTER SEGUROS', LOWER(v_email), 'owner'::text, true, v_default_org)
      ON CONFLICT (email) WHERE email IS NOT NULL DO UPDATE 
      SET user_id = v_master_id, role = 'owner', is_active = true, organization_id = v_default_org;
    END IF;
  END LOOP;
END $$;


-- 7. RESTAURAR CONFIGURAÇÃO DE SESSÃO DAS TRIGGERS
-- Reativa triggers normais e políticas RLS para garantir integridade após a carga de produção
SET session_replication_role = 'origin';

-- Limpar tabela temporária de apoio
DROP TABLE users_to_keep;

COMMIT;

-- ====================================================================================
-- FIM SCRIPT DE PREPARAÇÃO DE LEVA DE PRODUÇÃO DO SAFE-OS
-- ====================================================================================
