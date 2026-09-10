-- ############################################################################################
-- INSTRUÇÕES DE EXECUÇÃO NO SUPABASE SQL EDITOR
-- ############################################################################################
-- Devido a restrições do PostgreSQL, a adição de novos valores de ENUM não pode ser realizada
-- na mesma transação que faz uso deles. Execute estes scripts em duas etapas separadas:
--
-- ============================================================================================
-- ETAPA 1 (Copie do Bloco "Etapa 1" e execute primeiro. Não use blocos BEGIN/COMMIT nesta etapa)
-- ============================================================================================
--
-- ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'owner';
-- ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'financeiro';
-- ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'suporte';
-- ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'leitura';
-- ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'corretor';
--
-- ============================================================================================
-- ETAPA 2 (Execute este script após obter sucesso na Etapa 1)
-- ============================================================================================

BEGIN;

-- 1. CRIAÇÃO DA TABELA DE ORGANIZAÇÕES (SaaS Multi-Tenant)
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

-- 2. CRIAÇÃO DA TABELA DE REGISTROS DE AUDITORIA (AUDIT)
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID REFERENCES public.organizations(id),
  user_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL,
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

-- 3. CRIAÇÃO DA ORGANIZAÇÃO PADRÃO
INSERT INTO public.organizations (name, slug) 
VALUES ('Organizações MedSafe', 'organizacao-padrao')
ON CONFLICT (slug) DO NOTHING;

-- 4. CONFIGURAÇÃO DE COLUNAS DE MULTI-TENANCY E GATILHOS
DO $$
DECLARE
  v_default_org_id UUID;
  t TEXT;
BEGIN
  SELECT id INTO v_default_org_id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;

  FOR t IN SELECT table_name 
           FROM information_schema.tables 
           WHERE table_schema = 'public' 
           AND table_name IN ('profiles', 'clients', 'apolices', 'sinistros', 'produtos', 'renovacoes', 'client_documents', 'client_notes', 'activity_log', 'contas', 'custos_fixos', 'financeiro_historico', 'client_commission_terms', 'user_roles', 'team_members')
  LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id)', t);
    EXECUTE format('UPDATE public.%I SET organization_id = %L WHERE organization_id IS NULL', t, v_default_org_id);
  END LOOP;
END $$;

-- 5. CRIAR OU ATUALIZAR FUNÇÕES DE APOIO E ATRIBUIÇÃO
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

CREATE OR REPLACE FUNCTION public.fn_set_organization_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := (SELECT organization_id FROM public.profiles WHERE id = auth.uid() LIMIT 1);
  END IF;
  
  IF NEW.organization_id IS NULL THEN
    NEW.organization_id := (SELECT id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1);
  END IF;

  IF (TG_OP = 'UPDATE') THEN
    IF (OLD.organization_id IS DISTINCT FROM NEW.organization_id) AND 
       NOT (public.has_any_role(auth.uid(), ARRAY['owner'::app_role, 'admin'::app_role])) THEN
      RAISE EXCEPTION 'Não é permitido alterar a organização do registro.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

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

-- 6. ATRIBUIR OS GATILHOS (TRIGGERS) ÀS TABELAS PUBLICAS
DO $$
DECLARE
  t TEXT;
BEGIN
  FOR t IN SELECT table_name 
           FROM information_schema.tables 
           WHERE table_schema = 'public' 
           AND table_name IN ('profiles', 'clients', 'apolices', 'sinistros', 'produtos', 'renovacoes', 'client_documents', 'client_notes', 'activity_log', 'contas', 'custos_fixos', 'financeiro_historico', 'client_commission_terms', 'user_roles', 'team_members')
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS tr_set_org_%I ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER tr_set_org_%I BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_set_organization_id()', t, t);
    
    EXECUTE format('DROP TRIGGER IF EXISTS tr_audit_%I ON public.%I', t, t);
    EXECUTE format('CREATE TRIGGER tr_audit_%I AFTER INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log_trigger()', t, t);
  END LOOP;
END $$;

-- 7. REFORMULAÇÃO DE SEGURANÇA E RLS PARA EQUIPE (TEAM_MEMBERS)
DROP POLICY IF EXISTS "Role based team_members select" ON public.team_members;
DROP POLICY IF EXISTS "Admins gestores and administrativo can insert team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins gestores and administrativo can update team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins gestores and administrativo can delete team members" ON public.team_members;
DROP POLICY IF EXISTS "Delete only admin_owner team_members" ON public.team_members;
DROP POLICY IF EXISTS "Authenticated users can view team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins and gestores can insert team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins and gestores can update team members" ON public.team_members;
DROP POLICY IF EXISTS "Admins can delete team members" ON public.team_members;
DROP POLICY IF EXISTS "team_members_select_organization" ON public.team_members;
DROP POLICY IF EXISTS "team_members_insert_admin_owner_gestor" ON public.team_members;
DROP POLICY IF EXISTS "team_members_update_admin_owner_gestor" ON public.team_members;
DROP POLICY IF EXISTS "team_members_delete_admin_owner" ON public.team_members;

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

-- 8. REFORMULAÇÃO DE SEGURANÇA E RLS PARA PRODUTOS (PRODUTOS)
DROP POLICY IF EXISTS "produtos_select_active" ON public.produtos;
DROP POLICY IF EXISTS "produtos_insert_admin_gestor_administrativo" ON public.produtos;
DROP POLICY IF EXISTS "produtos_update_admin_gestor_administrativo" ON public.produtos;
DROP POLICY IF EXISTS "produtos_delete_admin" ON public.produtos;
DROP POLICY IF EXISTS "Delete only admin_owner produtos" ON public.produtos;
DROP POLICY IF EXISTS "Org isolation produtos" ON public.produtos;
DROP POLICY IF EXISTS "produtos_select_organization" ON public.produtos;
DROP POLICY IF EXISTS "produtos_insert_admin_owner_gestor" ON public.produtos;
DROP POLICY IF EXISTS "produtos_update_admin_owner_gestor" ON public.produtos;
DROP POLICY IF EXISTS "produtos_delete_admin_owner" ON public.produtos;

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

-- 9. REFORMULAÇÃO DE SEGURANÇA NO GERENCIAMENTO DE ROLES (USER_ROLES) (OWNER & ADM)
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

-- 10. REGRAS AUXILIARES DE COERÊNCIA PARA ORGANIZAÇÃO (ORGANIZATIONS)
DROP POLICY IF EXISTS "Users can view their own organization" ON public.organizations;
CREATE POLICY "Users can view their own organization" ON public.organizations
  FOR SELECT USING (id = public.get_my_org_id());

-- ============================================================================================
-- 11. ATRIBUIÇÃO AUTOMÁTICA OU CRIAÇÃO DO USUÁRIO MASTER (comercial@medsafecorretora.com.br)
-- ============================================================================================
DO $$
DECLARE
  v_user_id UUID;
  v_email TEXT := 'comercial@medsafecorretora.com.br';
  v_org_id UUID;
BEGIN
  -- Recupera a organização padrão se o perfil não tiver uma
  SELECT id INTO v_org_id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;

  -- Procura o ID do usuário na tabela de autenticação auth.users
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;

  IF v_user_id IS NOT NULL THEN
    -- Atualiza ou Insere Perfil como Dono/Proprietário
    INSERT INTO public.profiles (id, full_name, email, organization_id, updated_at)
    VALUES (v_user_id, 'MASTER MEDSAFE', v_email, v_org_id, now())
    ON CONFLICT (id) DO UPDATE 
    SET full_name = 'MASTER MEDSAFE', organization_id = v_org_id, updated_at = now();

    -- Atribui a Role de 'owner' (Proprietário/Master) no controle de acesso
    IF NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_user_id AND role = 'owner'::public.app_role) THEN
      INSERT INTO public.user_roles (user_id, role, organization_id)
      VALUES (v_user_id, 'owner'::public.app_role, v_org_id);
    ELSE
      UPDATE public.user_roles 
      SET organization_id = v_org_id 
      WHERE user_id = v_user_id AND role = 'owner'::public.app_role;
    END IF;

    -- Vincula ou atualiza na tabela de Membros da Equipe (Team Members)
    IF EXISTS (SELECT 1 FROM public.team_members WHERE email = v_email) THEN
      UPDATE public.team_members 
      SET user_id = v_user_id, full_name = 'MASTER MEDSAFE', role = 'owner', is_active = true, organization_id = v_org_id, updated_at = now()
      WHERE email = v_email;
    ELSE
      INSERT INTO public.team_members (user_id, full_name, email, role, is_active, organization_id)
      VALUES (v_user_id, 'MASTER MEDSAFE', v_email, 'owner', true, v_org_id);
    END IF;

    RAISE NOTICE 'Usuário % (ID: %) configurado com sucesso como MASTER do sistema!', v_email, v_user_id;
  ELSE
    RAISE NOTICE 'O Usuário % ainda não cadastrou-se no banco Auth de produção. Registre-o no app ou convide-o via Supabase Auth. Uma vez criado o usuário, o script poderá vinculá-lo como MASTER.', v_email;
  END IF;
END $$;

COMMIT;
