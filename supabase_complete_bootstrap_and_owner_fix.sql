-- ############################################################################################
-- SCRIPT COMPLETO DE BOOTSTRAP E CORREÇÃO DE PERMISSÕES - SAFE OS
-- APLICAÇÃO: EXECUTAR ESTE SCRIPT NO "SQL EDITOR" DO SUPABASE
-- ESTE SCRIPT IRÁ AUTOMATICAMENTE:
--   1. Criar a tabela public.organizations se ela não existir.
--   2. Garantir que as colunas organization_id e os Enums de permissão necessários existam em todas as tabelas.
--   3. Criar os registros de organização padrão.
--   4. Habilitar gatilhos para associar registros automaticamente à organização do operador.
--   5. Atualizar as políticas de RLS e segurança do usuário Master (Sócio/Owner/Owner) e Team Members.
-- ############################################################################################

BEGIN;

-- ==========================================
-- 1. CRIAÇÃO DOS ENUMS E EXPANSORES DE ROLES
-- ==========================================
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'app_role') THEN
    CREATE TYPE public.app_role AS ENUM ('admin', 'gestor', 'vendedor', 'administrativo', 'owner', 'financeiro', 'suporte', 'leitura', 'corretor');
  ELSE
    -- Adiciona novos valores de forma segura a um Enum existente
    BEGIN
      ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'owner';
    EXCEPTION WHEN others THEN NULL;
    END;
    
    BEGIN
      ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'financeiro';
    EXCEPTION WHEN others THEN NULL;
    END;
    
    BEGIN
      ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'suporte';
    EXCEPTION WHEN others THEN NULL;
    END;
    
    BEGIN
      ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'leitura';
    EXCEPTION WHEN others THEN NULL;
    END;
    
    BEGIN
      ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'corretor';
    EXCEPTION WHEN others THEN NULL;
    END;
  END IF;
END $$;


-- =========================================================
-- 2. CRIAÇÃO DA TABELA DE ORGANIZAÇÕES (SaaS Multi-Tenant)
-- =========================================================
CREATE TABLE IF NOT EXISTS public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  active BOOLEAN DEFAULT true,
  settings JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Ativa RLS na tabela de organizações
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;


-- =========================================================
-- 3. CRIAÇÃO DA TABELA DE REGISTROS DE AUDITORIA (AUDIT)
-- =========================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id),
  user_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE', 'SELECT'
  table_name TEXT NOT NULL,
  record_id UUID,
  old_data JSONB,
  new_data JSONB,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Ativa RLS nos logs de auditoria
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;


-- ====================================================
-- 4. CRIAÇÃO DA ORGANIZAÇÃO PADRÃO
-- ====================================================
INSERT INTO public.organizations (name, slug) 
VALUES ('Organização Padrão', 'organizacao-padrao')
ON CONFLICT (slug) DO NOTHING;


-- ====================================================
-- 5. CONFIGURAÇÃO DE COLUNAS DE MULTITE-NANCY E GATILHOS
-- ====================================================
DO $$
DECLARE
  v_default_org_id UUID;
  t TEXT;
BEGIN
  -- Recupera o ID da Organização Padrão
  SELECT id INTO v_default_org_id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;

  -- Lista de tabelas que precisam suportar isolamento por organização
  FOR t IN SELECT table_name 
           FROM information_schema.tables 
           WHERE table_schema = 'public' 
           AND table_name IN ('profiles', 'clients', 'apolices', 'sinistros', 'produtos', 'renovacoes', 'client_documents', 'client_notes', 'activity_log', 'contas', 'custos_fixos', 'financeiro_historico', 'client_commission_terms', 'user_roles', 'team_members')
  LOOP
    -- AdicionaColuna se ela ainda não existir
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id)', t);
    
    -- Preenche com a organização padrão as linhas existentes
    EXECUTE format('UPDATE public.%I SET organization_id = %L WHERE organization_id IS NULL', t, v_default_org_id);
  END LOOP;
END $$;


-- ====================================================
-- 6. CRIAR OU ATUALIZAR FUNÇÕES DE APOIO E ATRIBUIÇÃO
-- ====================================================

-- Função robusta e autoregenerativa que retorna o ID da organização do usuário logado
CREATE OR REPLACE FUNCTION public.get_my_org_id()
RETURNS UUID AS $$
DECLARE
  v_org_id UUID;
BEGIN
  -- 1. Tenta obter do perfil do usuário
  SELECT organization_id INTO v_org_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
  
  -- 2. Se for nula, tenta obter do metadado do JWT
  IF v_org_id IS NULL THEN
    BEGIN
      v_org_id := (auth.jwt() -> 'user_metadata' ->> 'organization_id')::UUID;
    EXCEPTION WHEN others THEN
      v_org_id := NULL;
    END;
  END IF;

  -- 3. Se ainda for nula, pega do primeiro registro nas user_roles
  IF v_org_id IS NULL THEN
    SELECT organization_id INTO v_org_id FROM public.user_roles WHERE user_id = auth.uid() LIMIT 1;
  END IF;

  -- 4. Em último caso, recorre à organização padrão
  IF v_org_id IS NULL THEN
    SELECT id INTO v_org_id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;
  END IF;

  RETURN v_org_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Função auxiliar que checa as roles do usuário atual com bypass total para desenvolvedores/administradores masters
CREATE OR REPLACE FUNCTION public.has_any_role(p_user_id UUID, p_roles app_role[])
RETURNS BOOLEAN AS $$
DECLARE
  v_is_master BOOLEAN := false;
  v_email TEXT;
BEGIN
  -- 1. Checa por email master no JWT atual
  v_email := LOWER(auth.jwt() ->> 'email');
  IF v_email IN ('nexusaionline@gmail.com', 'comercial@medsafecorretora.com.br') THEN
    v_is_master := true;
  END IF;

  -- 2. Na falta de JWT ou se p_user_id explícito não-atual, checa na tabela auth.users
  IF NOT v_is_master AND p_user_id IS NOT NULL THEN
    SELECT LOWER(email) INTO v_email FROM auth.users WHERE id = p_user_id LIMIT 1;
    IF v_email IN ('nexusaionline@gmail.com', 'comercial@medsafecorretora.com.br') THEN
      v_is_master := true;
    END IF;
  END IF;

  -- Bypass total se for usuário MASTER para papéis críticos administrativos/owner
  IF v_is_master AND ('owner'::app_role = ANY(p_roles) OR 'admin'::app_role = ANY(p_roles)) THEN
    RETURN true;
  END IF;

  -- 3. Caso contrário, consulta as user_roles comuns do banco
  RETURN EXISTS (
    SELECT 1 FROM public.user_roles 
    WHERE user_id = p_user_id AND role = ANY(p_roles)
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Trigger Function para atribuir a organização automaticamente no INSERT
CREATE OR REPLACE FUNCTION public.fn_set_organization_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := (SELECT organization_id FROM public.profiles WHERE id = auth.uid() LIMIT 1);
  END IF;
  
  -- Fallback para organização padrão se ainda for NULL
  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := (SELECT id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1);
  END IF;

  -- Impede a alteração de organização no UPDATE exceto para Admins/Owners
  IF (TG_OP = 'UPDATE') THEN
    IF (OLD.organization_id IS DISTINCT FROM NEW.organization_id) AND 
       NOT (public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role])) THEN
      RAISE EXCEPTION 'Não é permitido alterar a organização do registro.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger Function para gravação de logs de auditoria
CREATE OR REPLACE FUNCTION public.fn_audit_log_trigger()
RETURNS TRIGGER AS $$
DECLARE
  v_org_id UUID;
  v_user_id UUID := auth.uid();
BEGIN
  IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
    v_org_id := OLD.organization_id;
  ELSE
    v_org_id := NEW.organization_id;
  END IF;

  -- Fallback de organização
  IF v_org_id IS NULL THEN
    v_org_id := (SELECT organization_id FROM public.profiles WHERE id = COALESCE(v_user_id, NEW.user_id, OLD.user_id) LIMIT 1);
  END IF;

  INSERT INTO public.audit_logs (
    organization_id,
    user_id,
    action,
    table_name,
    record_id,
    old_data,
    new_data
  ) VALUES (
    v_org_id,
    v_user_id,
    TG_OP,
    TG_TABLE_NAME,
    COALESCE(NEW.id, OLD.id),
    CASE WHEN TG_OP IN ('DELETE', 'UPDATE') THEN to_jsonb(OLD) ELSE NULL END,
    CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) ELSE NULL END
  );

  IF (TG_OP = 'DELETE') THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ====================================================
-- 7. ATRIBUIR OS GATILHOS (TRIGGERS) ÀS TABELAS PUBLICAS
-- ====================================================
DO $$
DECLARE
  t TEXT;
BEGIN
  FOR t IN SELECT table_name 
           FROM information_schema.tables 
           WHERE table_schema = 'public' 
           AND table_name IN ('profiles', 'clients', 'apolices', 'sinistros', 'produtos', 'renovacoes', 'client_documents', 'client_notes', 'activity_log', 'contas', 'custos_fixos', 'financeiro_historico', 'client_commission_terms', 'user_roles', 'team_members')
  LOOP
    -- Gatilho de Autodeclaração de Organização
    EXECUTE format('DROP TRIGGER IF EXISTS tr_set_org_%I ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER tr_set_org_%I BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_set_organization_id()', t, t);
    
    -- Gatilho de Auditoria
    EXECUTE format('DROP TRIGGER IF EXISTS tr_audit_%I ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER tr_audit_%I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log_trigger()', t, t);
  END LOOP;
END $$;


-- ====================================================
-- 8. REFORMULAÇÃO DE SEGURANÇA E RLS PARA EQUIPE (TEAM_MEMBERS)
-- ====================================================

-- Remove políticas antigas e conflitantes de Team Members
DROP POLICY IF EXISTS "Role based team_members select" ON public.team_members;
DROP POLICY IF EXISTS "Admins gestores and administrativo can insert team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins gestores and administrativo can update team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins gestores and administrativo can delete team members" ON public.team_members;
DROP POLICY IF EXISTS "Delete only admin_owner team_members" ON public.team_members;
DROP POLICY IF EXISTS "Authenticated users can view team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins and gestores can insert team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins and gestores can update team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins can delete team members" ON public.team_members;

-- Novas políticas completas para Team Members com isolamento multi-tenant
CREATE POLICY "team_members_select_organization" ON public.team_members
  FOR SELECT USING (organization_id = public.get_my_org_id());

CREATE POLICY "team_members_insert_admin_owner_gestor" ON public.team_members
  FOR INSERT WITH CHECK (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role, 'gestor'::app_role, 'administrativo'::app_role])
    )
  );

CREATE POLICY "team_members_update_admin_owner_gestor" ON public.team_members
  FOR UPDATE USING (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role, 'gestor'::app_role, 'administrativo'::app_role])
    )
  ) WITH CHECK (
    organization_id = public.get_my_org_id()
  );

CREATE POLICY "team_members_delete_admin_owner" ON public.team_members
  FOR DELETE USING (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role])
    )
  );


-- ====================================================
-- 9. REFORMULAÇÃO DE SEGURANÇA E RLS PARA PRODUTOS (PRODUTOS)
-- ====================================================

-- Remove políticas antigas de Produtos
DROP POLICY IF EXISTS "produtos_select_active" ON public.produtos;
DROP POLICY IF EXISTS "produtos_insert_admin_gestor_administrativo" ON public.produtos;
DROP POLICY IF EXISTS "produtos_update_admin_gestor_administrativo" ON public.produtos;
DROP POLICY IF EXISTS "produtos_delete_admin" ON public.produtos;
DROP POLICY IF EXISTS "Delete only admin_owner produtos" ON public.produtos;
DROP POLICY IF EXISTS "Org isolation produtos" ON public.produtos;

-- Novas políticas completas para Produtos
CREATE POLICY "produtos_select_organization" ON public.produtos
  FOR SELECT USING (organization_id = public.get_my_org_id());

CREATE POLICY "produtos_insert_admin_owner_gestor" ON public.produtos
  FOR INSERT WITH CHECK (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role, 'gestor'::app_role, 'administrativo'::app_role])
    )
  );

CREATE POLICY "produtos_update_admin_owner_gestor" ON public.produtos
  FOR UPDATE USING (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role, 'gestor'::app_role, 'administrativo'::app_role])
    )
  ) WITH CHECK (
    organization_id = public.get_my_org_id()
  );

CREATE POLICY "produtos_delete_admin_owner" ON public.produtos
  FOR DELETE USING (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role])
    )
  );


-- ======================================================
-- 10. REFORMULAÇÃO DE SEGURANÇA NO GERENCIAMENTO DE ROLES
-- ======================================================
DROP POLICY IF EXISTS "Admins can manage all roles" ON public.user_roles;
DROP POLICY IF EXISTS "user_roles_manage_admin_owner" ON public.user_roles;

CREATE POLICY "user_roles_manage_admin_owner" ON public.user_roles
  FOR ALL USING (
    organization_id = public.get_my_org_id() AND (
      public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role])
    )
  ) WITH CHECK (
    organization_id = public.get_my_org_id()
  );


-- ======================================================
-- 11. REGRAS AUXILIARES DE COERÊNCIA PARA ORGANIZAÇÃO (ORGANIZATIONS)
-- ======================================================
DROP POLICY IF EXISTS "Users can view their own organization" ON public.organizations;
CREATE POLICY "Users can view their own organization" ON public.organizations
  FOR SELECT USING (id = public.get_my_org_id());

COMMIT;
