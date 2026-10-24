# Highway Roadster no Roblox · passo a passo

São só **2 scripts**. Todo o resto (pista, carro, tráfego, polícia, HUD, céu synthwave) é criado por código quando o jogo roda.

| Arquivo | Onde colar no Studio | Tipo |
|---|---|---|
| `HighwayServer.server.lua` | **ServerScriptService** | Script |
| `HighwayClient.client.lua` | **StarterPlayer > StarterPlayerScripts** | LocalScript |

## 1. Criar o projeto
1. Abra o **Roblox Studio** e faça login.
2. **New > Baseplate**.
3. **File > Save to Roblox As...** e dê um nome (ex.: "Highway Roadster"). Só precisa salvar uma vez.

## 2. Colar o script do servidor
1. No painel **Explorer** (se não aparecer: aba **View > Explorer**), passe o mouse em **ServerScriptService**, clique no **+** e escolha **Script**.
2. Renomeie para `HighwayServer` (F2).
3. Apague o `print("Hello world!")`, abra `HighwayServer.server.lua`, copie **tudo** e cole.

## 3. Colar o script do cliente
1. No Explorer, abra **StarterPlayer**. Passe o mouse em **StarterPlayerScripts**, clique no **+** e escolha **LocalScript** (tem que ser *Local*).
2. Renomeie para `HighwayClient`.
3. Apague o conteúdo, copie **tudo** de `HighwayClient.client.lua` e cole.

## 4. Ligar o ranking global
1. **Home > Game Settings > Security**.
2. Ligue **Enable Studio Access to API Services** e clique em **Save**.
   (Sem isso o jogo funciona, mas o ranking aparece como "offline" no Studio.)

## 5. Testar
- Clique em **Play** (F5). O menu aparece, clique em **PLAY**: 3-2-1 e a corrida começa.
- Se der erro, abra **View > Output** e me mande o print da mensagem vermelha.
- Celular: em **Test > Device**, escolha um celular para ver os botões ◀ ▶ JUMP SLAM NITRO.

## 6. Publicar
1. **File > Publish to Roblox**.
2. No site (create.roblox.com > Creations), abra o jogo e vá em **Configure**: nome, descrição, ícone e thumbnails.
3. Em **Permissions**, mude para **Public** quando estiver pronto.
   **Nome:** não use "Tesla" nem "Cybertruck" (marca registrada; o Roblox derruba). "Highway Roadster" serve.

## 7. Sons (opcional)
O Roblox só toca áudio do próprio catálogo. No Studio, abra **View > Toolbox > Audio** e procure por: `electric car`, `police siren loop`, `whoosh`, `explosion`, `car crash`, `countdown beep`.
Clique com o botão direito no som > **Copy Asset ID** e cole no topo do `HighwayClient`, na tabela `SOUND_IDS`:

```lua
local SOUND_IDS = {
	engine = "rbxassetid://COLE_AQUI",
	siren = "rbxassetid://COLE_AQUI",
	...
}
```

## Controles
| PC | Controle | Celular | Ação |
|---|---|---|---|
| ← → / A D | D-Pad | ◀ ▶ | Trocar faixa · no ar: barrel roll |
| ↑ / W / Espaço | A | JUMP | Pular · segurar = voar · no ar: front flip |
| ↓ / S | B | SLAM | Slam (no ar) |
| Shift | X / R2 | NITRO | Nitro boost |
| R / Enter | A | — | Retry |

## Ajustes rápidos (topo do HighwayClient)
- `K = 3.2`: tamanho do mundo (studs por metro).
- `HEAT_PER_STAR = 3`: quantos carros destruídos valem 1 estrela de procurado.
- `LANES`, `COMBO_TIME`: faixas e tempo do combo.

## Se algo parecer estranho
- **Capô/traseira do carro virados ao contrário:** troque de lugar as duas linhas `WedgePart` do capô/traseira (as que têm `CFrame.Angles(0, math.pi, 0)` ficam na outra). Não deu para testar no Studio daqui, então esse é o ponto mais provável de ajuste visual.
- **Personagem aparecendo:** ele fica parado no spawn, longe da pista (a pista fica 400 studs acima). Pode apagar o SpawnLocation/Baseplate se quiser, o jogo não depende deles.
