# Fase 6 — acabamento (acessibilidade, movimento, localização, ícone)

## 1. Localização PT-BR / inglês (String Catalog)
- `Ice/Resources/Localizable.xcstrings`: inglês é a língua-fonte; **pt-BR completo** (177 chaves). A interface segue o idioma do sistema (o app tem `en.lproj` e `pt-BR.lproj`; região `pt-BR` no projeto).
- **"Barra do Trincano"**: toda frase com "Trincano Bar" fica "Barra do Trincano" em PT-BR; o nome do produto nunca é traduzido (testado).
- Strings fora do SwiftUI (menus da barra, alertas, permissões, nomes de seção, importação do Ice) passaram a usar `String(localized:)`.
- `STRING_CATALOG_GENERATE_SYMBOLS = NO` (chaves em linguagem natural geram símbolos conflitantes).
- Garantias: `LocalizationCatalogTests` (pt-BR presente e não vazio, placeholders iguais, "Barra do Trincano", nome do produto preservado) e `scripts/extract-strings.py check` (roda no `scripts/check.sh`): falha se o compilador extrair uma string que não está no catálogo ou se faltar pt-BR.
- Não traduzido de propósito: a nota legada de migração do Ice (`Migration.swift`) e mensagens de log.
- Validação no pacote compilado: `plutil -p …/pt-BR.lproj/Localizable.strings` mostra "Trincano Bar" => "Barra do Trincano". **Não** abri o app em PT-BR (o Paulo está usando o instalado); roteiro: `defaults write br.com.pilutech.trincano AppleLanguages '(pt-BR)'` e reabrir.

## 2. Movimento reduzido e transições de 150 a 300 ms
`MotionPolicy` (puro, testado) + `Motion` (lê `accessibilityDisplayShouldReduceMotion`): os fades do overlay de aparência, a animação de reordenar no editor de layout e a mudança de cor da Barra passam a durar entre 150 e 300 ms e a **zero** com "Reduzir movimento". A Barra do Trincano continua aparecendo sem animação (decisão de latência: 34 ms medidos na fase 5).

## 3. VoiceOver
- Itens de controle da barra de menus: rótulo ("Trincano", "Divisor da seção escondida", "Divisor da seção sempre escondida") e ajuda.
- Editor de layout (`LayoutBarItemView`): elemento de acessibilidade com papel botão, nome do item e ajuda "Arraste para mover…".
- Barra do Trincano: itens com papel de botão, ações "clique esquerdo/direito" localizadas.
- Busca: imagens decorativas ocultas do VoiceOver (o texto da linha já nomeia o item); botão "Clicar/Mostrar item" localizado; gravador de atalho com "Limpar/Gravar/Cancelar".
- **Não validado com VoiceOver ligado** (depende do Paulo); roteiro: ligar o VoiceOver (⌘F5), navegar a barra de menus, a Barra, os ajustes e o editor de layout.

## 3b. Correções da revisão do Lupa (PR #9)
- **Durações localizadas**: os 3 controles de duração concatenavam o número com " second/seconds" antes de virar `LocalizedStringKey`: essas chaves não existem no catálogo e a unidade ficava em inglês no pt-BR. Agora `DurationText` usa o formatador de medidas do sistema com o idioma da interface (plural e vírgula decimal corretos: "0 segundo", "1 segundo", "2 segundos", "0,1 segundo"; en: "0 seconds", "1 second", "2 seconds", "0.1 seconds"). **Vermelho comportamental** contra a concatenação antiga (12 falhas de asserção).
- Nome do conjunto de ícones (`Text(imageSet.name.rawValue)`) e títulos AppKit (editor de aparência, Barra, overlay) agora localizados.
- **VoiceOver do layout**: a `NSView` era anunciada como botão sem implementar pressionar nem mover. Agora `applyLayoutItemAccessibility` (a mesma função que a `LayoutBarItemView` chama) a anuncia como **imagem** (lida, não acionável), sem ajuda que prometa arrastar, e item não movível diz "…, não pode ser movido". Teste numa `NSView` real. Vermelho: 3 falhas. Ações de mover por VoiceOver ficam em `docs/pendencias.md`.
- `extract-strings.py` agora **falha** (código 2) se não extrair nenhuma string (build ausente). `Motion.duration(.reorder)` aplicado ao grupo de animação do layout.
- Limite honesto: o teste de acessibilidade usa uma `NSView` configurada pela mesma função, não a `LayoutBarItemView` inteira (depende de `AppState`).

## 4. Ícone: 3 propostas do designer (nada implementado ainda)
O subagente `designer` só propôs; as imagens estão em `docs/identidade/propostas-icone/` (SVG do app 1024, glifos escondido/visível 18 pt e prévias PNG). Todas fogem do cubo de gelo e do visual de apps pagos.
1. **Trinco** (ferrolho de latão num trilho de vidro; escondido = pino à esquerda, visível = à direita). "Trinco" está no nome. Ressalva: o glifo visível lembra um interruptor.
2. **Fenda** (silhueta do notch/pílula com uma trinca luminosa; escondido = bloco com fenda, visível = duas metades abertas). Amarra nome, notch e função. Paleta de brasa (#FF7A55), longe do azul do Ice. **Recomendada pelo designer** (e por mim: é a mais distinta e a que lê melhor a 18 pt).
3. **Trincheira** (barra de vidro com a Barra do Trincano abaixo, como beiral; roxo). Mais colorida; o glifo escondido pode lembrar um menu hambúrguer.
Para implementar a escolhida: converter os SVG em `AppIcon.appiconset` e em `ControlItemImages/<Nome>Fill/Stroke` (template), trocar `defaultIceIcon` e o uso de `iceCubeStroke` na busca e no Sobre, e (opcional) levar ao Icon Composer para o Liquid Glass real. **Aguarda a escolha do Paulo.**
