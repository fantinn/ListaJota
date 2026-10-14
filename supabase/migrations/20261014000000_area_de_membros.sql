-- Area de membros da ListaJota: o mesmo modelo da listafnc, consolidado no
-- estado final dela (as 9 migrations de la viraram esta uma, sem os dados).
--
-- Tres camadas, todas decididas aqui no banco:
--   anon        -> nao le nada;
--   comprador   -> le fornecedores ativos e categorias; da propria linha em
--                  membros so escreve ultimo_acesso;
--   admin       -> le e escreve tudo.
-- Estar logado nao basta: toda politica exige linha ativa em membros.

create extension if not exists unaccent;

-- Membros (compradores liberados e admins) -------------------------------

create table public.membros (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  criado_em timestamptz not null default now(),
  -- Sufixo aleatorio da senha gerada (nunca sequencial: com numero previsivel
  -- bastavam poucas tentativas para entrar na conta de outro comprador).
  sufixo text not null,
  admin boolean not null default false,
  ultimo_acesso timestamptz,
  ativo boolean not null default true,
  desativado_em timestamptz,
  motivo_desativacao text
);

alter table public.membros enable row level security;

create policy "membro le a propria linha"
  on public.membros for select to authenticated
  using (auth.uid() = id);

create policy "membro atualiza a propria linha"
  on public.membros for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- RLS controla linhas, nao colunas. Sem este corte por GRANT o comprador
-- se promoveria a admin com um PATCH.
revoke update on public.membros from authenticated;
grant update (ultimo_acesso) on public.membros to authenticated;
revoke all on public.membros from anon;

-- Funcoes auxiliares das politicas ----------------------------------------

create or replace function public.eh_membro()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.membros where id = auth.uid() and ativo) $$;

create or replace function public.eh_admin()
returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.membros where id = auth.uid() and admin) $$;

-- O EXECUTE vem do papel PUBLIC por padrao; so authenticated chama.
revoke execute on function public.eh_membro() from public, anon;
revoke execute on function public.eh_admin() from public, anon;
grant execute on function public.eh_membro() to authenticated;
grant execute on function public.eh_admin() to authenticated;

create or replace function public.tocar_atualizado_em()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  new.atualizado_em = now();
  return new;
end $$;

-- Fornecedores ------------------------------------------------------------

create table public.fornecedores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  categoria text,
  telefone text,
  instagram text,
  cidade text,
  estado text,
  observacoes text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index fornecedores_categoria_idx on public.fornecedores (categoria);
create index fornecedores_ativo_idx on public.fornecedores (ativo);

alter table public.fornecedores enable row level security;

create policy "membro le fornecedores ativos"
  on public.fornecedores for select to authenticated
  using (ativo and public.eh_membro());

create policy "admin le tudo"
  on public.fornecedores for select to authenticated using (public.eh_admin());

create policy "admin insere"
  on public.fornecedores for insert to authenticated with check (public.eh_admin());

create policy "admin atualiza"
  on public.fornecedores for update to authenticated
  using (public.eh_admin()) with check (public.eh_admin());

create policy "admin remove"
  on public.fornecedores for delete to authenticated using (public.eh_admin());

create trigger fornecedores_atualizado_em
  before update on public.fornecedores
  for each row execute function public.tocar_atualizado_em();

-- Categorias (nome e ordem que o comprador ve) ----------------------------

create table public.categorias (
  id uuid primary key default gen_random_uuid(),
  chave text unique not null,
  nome text not null,
  ordem integer not null default 0,
  criado_em timestamptz not null default now()
);

alter table public.categorias enable row level security;

create policy "membro le categorias" on public.categorias
  for select to authenticated using (public.eh_membro() or public.eh_admin());

create policy "admin insere categorias" on public.categorias
  for insert to authenticated with check (public.eh_admin());

create policy "admin atualiza categorias" on public.categorias
  for update to authenticated using (public.eh_admin()) with check (public.eh_admin());

create policy "admin remove categorias" on public.categorias
  for delete to authenticated using (public.eh_admin());

-- Compras vindas do postback da PerfectPay --------------------------------
-- Ninguem le pelo site: so a service_role das Edge Functions.

create table public.compras (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  -- Nunca o CPF em claro: so o hash, para conferir sem guardar o numero.
  cpf_hash text,
  codigo_venda text unique,
  status_enum integer,
  status_texto text,
  produto text,
  valor numeric,
  payload jsonb,
  recebido_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create index compras_email_idx on public.compras (lower(email));

alter table public.compras enable row level security;
revoke all on public.compras from anon, authenticated;

-- Freio contra quem fica chutando e-mail/CPF na pagina de ativacao --------

create table public.tentativas_ativacao (
  id bigserial primary key,
  ip text,
  email text,
  sucesso boolean not null default false,
  quando timestamptz not null default now()
);

create index tentativas_ip_idx on public.tentativas_ativacao (ip, quando desc);

alter table public.tentativas_ativacao enable row level security;
revoke all on public.tentativas_ativacao from anon, authenticated;
