# 🚗💨 HIGHWAY ROADSTER

Jogo de corrida arcade 3D no navegador: uma rodovia à beira-mar no fim de tarde, com um roadster elétrico, tráfego, manobras aéreas, combos e perseguição policial.

**▶ Jogar agora:** https://pedrolucas-ads.github.io/highway-roadster/

Funciona no PC e no celular, sem instalar nada. Feito com **Three.js r128**, com o arquivo da biblioteca incluído no repositório. Os gráficos são todos procedurais, sem nenhuma imagem externa:

- Céu de pôr do sol gerado por shader, com nuvens. O próprio céu serve de mapa de reflexo para a pintura e os vidros.
- Sombras reais do sol, materiais PBR (pintura metálica com verniz), tone mapping ACES e mar com ondas (normal map).
- Asfalto com marcas de pneu e faixas pintadas, coqueiros na praia, árvores, montanhas, postes e placas de rodovia.

A versão antiga, no estilo synthwave neon, continua em [`synthwave.html`](synthwave.html).

## Controles
| Tecla | Ação |
|---|---|
| `←` `→` / `A` `D` | Trocar de faixa |
| `↑` / `Espaço` / `W` | Pular · **segurar = voar** (gasta nitro) |
| `↓` / `S` (no ar) | **Slam**: mergulha e destrói os carros em volta |
| `Shift` | **Nitro boost** (atravessa e arremessa os carros) |
| No ar: `←` `→` | Barrel roll |
| No ar: `↑` | Front flip |
| `P` / `Esc` · `M` · `R` | Pausa · som · jogar de novo |

**No celular:**

| Gesto | Ação |
|---|---|
| Deslizar para o lado | Trocar de faixa |
| Deslizar para cima | Pular (segurar o dedo = voar) |
| Deslizar para baixo | Slam |
| Botão **NITRO** | Nitro boost |

## Pontuação
- **Largada:** contagem 3-2-1 numa rampa de treliça de aço.
- **Manobras que pontuam:** Barrel roll, Front flip, Perfect landing, Near miss, Smash, Stomp e Slam.
- **Streak:** cada manobra soma no combo, com multiplicador `xN` e barra de tempo.
- **Fim de jogo:** pousar no meio de uma manobra, ou bater de frente sem nitro.
- **Ranking:** fica salvo no próprio navegador.

## Polícia
- **Nível de procurado:** cada carro destruído aumenta o nível. Três destruições valem uma estrela.
- **Viaturas:** cada estrela chama uma viatura (no máximo 4), com giroflex e sirene.
- **Aviso na tela:** a borda pisca vermelho e azul quando uma viatura está na sua cola.
- **BUSTED:** encostar numa viatura sem nitro ou slam encerra a corrida.
- **COP DOWN:** derrubar uma viatura vale +500 pontos, mas aumenta o nível de procurado.
- **Como despistar:** fique 12 segundos sem destruir nada e as viaturas desistem.

## Versão Roblox
A pasta [`roblox/`](roblox/) tem:

- os 2 scripts Luau do jogo, um do cliente e um do servidor, com ranking global via DataStore;
- o passo a passo para montar no Roblox Studio: [`COMO_COLOCAR_NO_ROBLOX.md`](roblox/COMO_COLOCAR_NO_ROBLOX.md);
- as imagens da página do jogo.

## Rodar localmente
Basta abrir o `index.html` no navegador. Ele funciona offline, sem servidor.
