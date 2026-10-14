# ListaJota

Landing page da Lista de Fornecedores da Jota Multimarcas (`index.html`) e a
área de membros de quem comprou. A área de membros foi portada da listafnc e
funciona do mesmo jeito; o banco é outro (projeto Supabase `listajota`), então
compradores e fornecedores das duas listas não se misturam.

## Área de membros

| Arquivo | Função |
| --- | --- |
| `login.html` | Entrada do comprador (e-mail + senha). |
| `ativar.html` | O comprador libera o próprio acesso com e-mail + CPF da compra e escolhe a senha. |
| `membros.html` | A lista: busca, filtro por categoria, botão de WhatsApp. |
| `admin.html` | Painel do admin, em duas abas: **Fornecedores** (cadastrar, editar, ocultar, remover; renomear e reordenar as categorias) e **Acessos** (criar acesso na mão, bloquear, redefinir senha, excluir comprador). |
| `area.css`, `categorias-ui.js` | Estilo e ícones compartilhados pelas páginas acima. |
| `supabase-config.js` | URL e chave pública do projeto. |
| `supabase/migrations/` | Esquema do banco (tabelas, RLS, funções auxiliares). |
| `supabase/functions/` | `perfectpay` (postback de venda), `ativar`, `criar-membro`, `gerenciar-membros`. |
| `admin/` | Scripts locais com a service_role key: `criar-membro.mjs`, `importar-fornecedores.mjs`. |

Quem decide o acesso é o banco (RLS), não a página:

- **não logado**: não lê nada;
- **comprador** (linha ativa em `membros`): lê fornecedores ativos e as categorias;
- **admin** (`membros.admin = true`): lê e escreve tudo.

Contas de admin não se criam pelo painel, de propósito: o primeiro admin sai do
script local.

## Configurar (uma vez)

1. **Primeiro admin.** Em Supabase → projeto `listajota` → Project Settings → API,
   copie a `service_role` key. Depois:

   ```
   cd admin
   copy .env.example .env
   ```

   Cole a chave em `admin/.env`, ajuste `SITE_URL` para o domínio do site e rode:

   ```
   npm install
   node criar-membro.mjs seu@email.com --admin
   ```

   A senha aparece na tela. Entre em `login.html` e o botão **Editar** leva ao painel.

2. **Lista inicial.** Cadastre pelo painel ou importe um CSV
   (`nome` obrigatória; `categoria`, `telefone`, `instagram`, `cidade`, `estado`, `observacoes`):

   ```
   node admin/importar-fornecedores.mjs lista.csv
   ```

3. **PerfectPay.** Token do webhook gravado como segredo (nunca no repositório):

   ```
   supabase secrets set PERFECTPAY_TOKEN=o_token --project-ref psspiwoxfapkghavdodi
   ```

   - Webhook de vendas: `https://psspiwoxfapkghavdodi.supabase.co/functions/v1/perfectpay`
   - Página de pagamento aprovado do produto: `https://SEU-DOMINIO/ativar.html`

   Sem o segredo a função responde 503 e não processa nada.

A `service_role` key fica só em `admin/.env`, que o `.gitignore` já ignora.
