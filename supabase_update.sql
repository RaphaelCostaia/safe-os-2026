-- ############################################################################################
-- SCRIPT DE ATUALIZAÇÃO DO BANCO DE DADOS - MÓDULO DE COMISSÕES (IMUTABILIDADE E HISTÓRICO)
-- ############################################################################################

-- 1. ENUMS (Garanta que os tipos existam)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_type') THEN
        CREATE TYPE commission_type AS ENUM ('percentual', 'fixo', 'misto');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_status') THEN
        CREATE TYPE commission_status AS ENUM ('prevista', 'recebida', 'cancelada');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'commission_entry_type') THEN
        CREATE TYPE commission_entry_type AS ENUM ('receita_padrao', 'ajuste_manual', 'bonus', 'estorno');
    END IF;
END $$;

-- 2. TABELA DE TERMOS DE COMISSÃO (ACORDOS POR CLIENTE/PRODUTO)
CREATE TABLE IF NOT EXISTS public.client_commission_terms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    produto_id UUID REFERENCES public.produtos(id) ON DELETE SET NULL, -- Null se for genérico para o cliente
    type commission_type NOT NULL DEFAULT 'percentual',
    value NUMERIC(10, 2) NOT NULL, -- Percentual ou Valor Fixo
    description TEXT,
    starts_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ends_at TIMESTAMP WITH TIME ZONE, -- Fim de vigência (null se ativo)
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_commission_terms_client ON public.client_commission_terms(client_id);
CREATE INDEX IF NOT EXISTS idx_commission_terms_active ON public.client_commission_terms(is_active) WHERE is_active = TRUE;

-- 3. TABELA DE LANÇAMENTOS (EXTRATO DE COMISSÕES)
CREATE TABLE IF NOT EXISTS public.comissoes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    apolice_id UUID NOT NULL REFERENCES public.apolices(id) ON DELETE CASCADE,
    term_id UUID REFERENCES public.client_commission_terms(id), -- Link para a regra aplicada no momento
    competencia_mes INTEGER NOT NULL CHECK (competencia_mes BETWEEN 1 AND 12),
    competencia_ano INTEGER NOT NULL,
    valor_base_premio NUMERIC(15, 2) DEFAULT 0, -- Valor do prêmio que gerou a comissão
    valor_comissao NUMERIC(15, 2) NOT NULL, -- Valor líquido a receber/recebido
    status commission_status DEFAULT 'recebida',
    tipo_lancamento commission_entry_type DEFAULT 'receita_padrao',
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id)
);

-- Índices para performance e relatórios
CREATE INDEX IF NOT EXISTS idx_comissoes_client ON public.comissoes(client_id);
CREATE INDEX IF NOT EXISTS idx_comissoes_competencia ON public.comissoes(competencia_ano, competencia_mes);
CREATE INDEX IF NOT EXISTS idx_comissoes_apolice ON public.comissoes(apolice_id);

-- 4. SEGURANÇA (RLS)
ALTER TABLE public.client_commission_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comissoes ENABLE ROW LEVEL SECURITY;

-- Políticas de acesso (Assumindo acesso total para usuários autenticados da mesma organização)
-- Nota: Em produção real, você filtraria por organization_id se houver múltiplos corretores no mesmo banco.

CREATE POLICY "Allow all for authenticated users on commission_terms" 
ON public.client_commission_terms FOR ALL 
USING (auth.role() = 'authenticated')
WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Allow all for authenticated users on comissoes" 
ON public.comissoes FOR ALL 
USING (auth.role() = 'authenticated')
WITH CHECK (auth.role() = 'authenticated');

-- 5. TRIGGER PARA GARANTIR IMUTABILIDADE (OPCIONAL MAS RECOMENDADO)
-- Evita a edição de valores de comissão já registrados, forçando novos lançamentos de ajuste.
CREATE OR REPLACE FUNCTION protect_commission_entries()
RETURNS TRIGGER AS $$
BEGIN
    IF (OLD.status = 'recebida') THEN
        RAISE EXCEPTION 'Registros de comissão recebida não podem ser editados. Crie um lançamento de ajuste.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger comentada por padrão, habilite se desejar rigor absoluto
-- CREATE TRIGGER trg_protect_commissions 
-- BEFORE UPDATE ON public.comissoes
-- FOR EACH ROW EXECUTE FUNCTION protect_commission_entries();

-- 6. DADOS PARA TESTE (Opcional - Criar um termo padrão para quem não tem)
-- INSERT INTO public.client_commission_terms (client_id, type, value, description)
-- SELECT id, 'percentual', 15.00, 'Acordo padrão inicial' FROM public.clients LIMIT 5;
