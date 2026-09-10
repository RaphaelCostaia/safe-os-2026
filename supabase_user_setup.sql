-- ############################################################################################
-- SCRIPT DE INFRAESTRUTURA DE USUÁRIOS - PERMISSÕES E PERFIS AUTOMÁTICOS
-- ############################################################################################

-- Garante que existe o índice herdeiro do ON CONFLICT para email
CREATE UNIQUE INDEX IF NOT EXISTS team_members_email_uidx ON public.team_members (email) WHERE email IS NOT NULL;

-- 1. FUNÇÃO PARA CRIAR PERFIL E ROLE AUTOMATICAMENTE NO SIGNUP
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  default_role public.app_role;
BEGIN
  -- Tenta pegar a role dos metadados, ou usa 'vendedor' como fallback
  BEGIN
    default_role := (new.raw_user_meta_data->>'role')::public.app_role;
  EXCEPTION WHEN OTHERS THEN
    default_role := 'vendedor';
  END;

  -- 1. Cria o Perfil
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (
    new.id, 
    COALESCE(new.raw_user_meta_data->>'full_name', 'Usuário Novo'), 
    new.email
  )
  ON CONFLICT (id) DO NOTHING;

  -- 2. Atribui a Role
  INSERT INTO public.user_roles (user_id, role)
  VALUES (new.id, default_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  -- 3. Cria entrada em Team Members (opcional, dependendo da sua lógica)
  IF new.email IS NOT NULL THEN
    INSERT INTO public.team_members (user_id, full_name, email, role, is_active)
    VALUES (
      new.id, 
      COALESCE(new.raw_user_meta_data->>'full_name', 'Usuário Novo'), 
      new.email, 
      default_role::text,
      true
    )
    ON CONFLICT (email) WHERE email IS NOT NULL DO UPDATE SET user_id = EXCLUDED.user_id, role = EXCLUDED.role;
  ELSE
    INSERT INTO public.team_members (user_id, full_name, role, is_active)
    VALUES (
      new.id, 
      COALESCE(new.raw_user_meta_data->>'full_name', 'Usuário Novo'), 
      default_role::text,
      true
    );
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. TRIGGER NO AUTH.USERS
-- Remove se já existir para evitar duplicidade
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. GARANTIR QUE AS TABELAS TÊM RLS E POLÍTICAS BÁSICAS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

-- Políticas de Perfil (Usuário vê o próprio perfil)
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- Políticas de Roles (Usuário vê a própria role)
DROP POLICY IF EXISTS "Users can view own role" ON public.user_roles;
CREATE POLICY "Users can view own role" ON public.user_roles
  FOR SELECT USING (auth.uid() = user_id);

-- 4. FUNÇÃO PARA REPARAR USUÁRIOS EXISTENTES (Caso algum tenha ficado sem role)
-- Você pode rodar isso se já criou contas que não estão entrando
-- SELECT public.handle_new_user() FROM auth.users WHERE id NOT IN (SELECT user_id FROM public.user_roles);
