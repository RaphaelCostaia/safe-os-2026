-- ############################################################################################
-- SCRIPT DEFINITIVO DE CRIAÇÃO E CONFIGURAÇÃO DO USUÁRIO MASTER (SafeOS / MedSafe)
-- ############################################################################################
-- E-mail Master: comercial@medsafecorretora.com.br
-- Execute este script completo no SQL Editor do seu Dashboard Supabase.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Garante que a função do trigger não falhe quando executada no SQL Editor (onde auth.uid() é null)
CREATE OR REPLACE FUNCTION public.fn_set_organization_id()
RETURNS TRIGGER AS $$
DECLARE
  v_default_id UUID;
BEGIN
  -- Se já foi fornecido explicitamente no INSERT, respeita
  IF NEW.organization_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Tenta obter do perfil do usuário autenticado atual
  IF auth.uid() IS NOT NULL THEN
    SELECT organization_id INTO NEW.organization_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
  END IF;
  
  -- Se ainda for nulo, busca a organização padrão pelo slug
  IF NEW.organization_id IS NULL THEN
    SELECT id INTO NEW.organization_id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;
  END IF;

  -- Se ainda for nulo, pega a primeira organização disponível no banco
  IF NEW.organization_id IS NULL THEN
    SELECT id INTO NEW.organization_id FROM public.organizations ORDER BY created_at ASC LIMIT 1;
  END IF;

  -- Se não existir nenhuma organização, cria a organização padrão
  IF NEW.organization_id IS NULL THEN
    INSERT INTO public.organizations (name, slug, active)
    VALUES ('MedSafe Corretora', 'organizacao-padrao', true)
    RETURNING id INTO NEW.organization_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Bloco principal de criação e elevação a MASTER
DO $$
DECLARE
  v_user_id UUID;
  v_email TEXT := 'comercial@medsafecorretora.com.br';
  v_name TEXT := 'Master MedSafe';
  v_password TEXT := 'MedSafe@2026'; -- Senha inicial provisória
  v_encrypted_pw TEXT;
  v_org_id UUID;
BEGIN
  -- 2.1. Obter ou criar organização padrão
  SELECT id INTO v_org_id FROM public.organizations WHERE slug = 'organizacao-padrao' LIMIT 1;
  
  IF v_org_id IS NULL THEN
    SELECT id INTO v_org_id FROM public.organizations ORDER BY created_at ASC LIMIT 1;
  END IF;

  IF v_org_id IS NULL THEN
    INSERT INTO public.organizations (name, slug, active)
    VALUES ('MedSafe Corretora', 'organizacao-padrao', true)
    RETURNING id INTO v_org_id;
  END IF;

  -- 2.2. Verificar se o usuário já existe em auth.users
  SELECT id INTO v_user_id FROM auth.users WHERE email = v_email;

  IF v_user_id IS NULL THEN
    v_user_id := gen_random_uuid();
    v_encrypted_pw := crypt(v_password, gen_salt('bf'));

    -- Cria o usuário em auth.users com e-mail já confirmado
    INSERT INTO auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      v_email,
      v_encrypted_pw,
      now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb,
      jsonb_build_object('full_name', v_name, 'role', 'owner', 'organization_id', v_org_id),
      now(),
      now()
    );

    -- Cria identidade em auth.identities
    INSERT INTO auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      provider_id,
      last_sign_in_at,
      created_at,
      updated_at
    ) VALUES (
      gen_random_uuid(),
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email),
      'email',
      v_user_id::text,
      now(),
      now(),
      now()
    ) ON CONFLICT DO NOTHING;

    RAISE NOTICE 'Usuário Auth criado com sucesso: % (ID: %)', v_email, v_user_id;
  ELSE
    RAISE NOTICE 'Usuário Auth já existente: % (ID: %)', v_email, v_user_id;
  END IF;

  -- 2.3. Insere/Atualiza o Perfil com organization_id explícito
  INSERT INTO public.profiles (
    id, 
    full_name, 
    email, 
    organization_id, 
    updated_at
  )
  VALUES (
    v_user_id, 
    v_name, 
    v_email, 
    v_org_id, 
    now()
  )
  ON CONFLICT (id) DO UPDATE 
  SET 
    full_name = v_name, 
    email = v_email, 
    organization_id = COALESCE(public.profiles.organization_id, v_org_id),
    updated_at = now();

  -- 2.4. Atribui a Role de 'owner' (Master do Sistema) em public.user_roles
  BEGIN
    INSERT INTO public.user_roles (user_id, role, organization_id)
    VALUES (v_user_id, 'owner'::public.app_role, v_org_id)
    ON CONFLICT (user_id, role) DO UPDATE SET organization_id = COALESCE(public.user_roles.organization_id, v_org_id);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.user_roles (user_id, role, organization_id)
    VALUES (v_user_id, 'owner'::text, v_org_id)
    ON CONFLICT DO NOTHING;
  END;

  -- 2.5. Garante que está na tabela de membros da equipe (Team Members)
  INSERT INTO public.team_members (
    user_id, 
    full_name, 
    email, 
    role, 
    is_active, 
    organization_id
  )
  VALUES (
    v_user_id, 
    v_name, 
    v_email, 
    'owner', 
    true, 
    v_org_id
  )
  ON CONFLICT (email) WHERE email IS NOT NULL DO UPDATE 
  SET 
    user_id = v_user_id,
    full_name = v_name,
    role = 'owner', 
    is_active = true,
    organization_id = COALESCE(public.team_members.organization_id, v_org_id);

  RAISE NOTICE '>>> SUCESSO: Usuário % configurado como MASTER (owner) com Organização % <<<', v_email, v_org_id;
END $$;


