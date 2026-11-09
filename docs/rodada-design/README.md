# Rodada de design (Fable 5.2, escolhas do Paulo em 09/11/2026)

Canvas: https://claude.ai/artifact/BZG18TuyNFaJoXbjiK6mLi. Escolhas: Barra **B**, Organização **A**, Geral **B**, Busca **A**, Sobre **B**. Só UI, sem mudar regra de negócio. Três PRs em sequência (todos tocam o `Localizable.xcstrings`: mergear na ordem, senão há conflito de catálogo).

## PR 1: Sobre B, Busca A, Organização A, títulos curtos
- **Barra lateral**: pt-BR "Organização" e "Aparência" (eram 29 e 27 caracteres). A chave também é o título da janela, então ele encurta junto. Teste: `sidebarTitlesFitTheSidebarInPortuguese` (≤ 16 caracteres; falhou antes da correção).
- **Sobre**: ficha de procedência (origem, licença, modificado por, código-fonte, outros créditos, privacidade). Valores longos quebram na linha; a barra de 6 botões virou 2 (Relatar um problema, Sair). Em janela baixa a ficha rola.
- **Busca**: contagem no rodapé (`MenuBarSearchSummary`, testada), atalhos ↑↓ ↩ esc sempre visíveis, ação (Clicar/Mostrar item ↩) na linha selecionada, nome longo truncado com tooltip, estado "sem resultados" citando a busca. Nenhuma animação.
- **Organização**: contagem por seção (plural no catálogo), estado vazio ("Arraste itens para cá") e nota de itens atrás do notch na seção Visível (`SectionCountSummary`, testada; só aparece em tela com notch).
- **Não feito (fica para depois)**: marcar cada item atrás do notch dentro do trilho (só há a contagem e a nota).

## Roteiro ao vivo para o Paulo (PR 1)
1. Ajustes em pt-BR: a barra lateral não corta "Organização"/"Aparência".
2. Sobre: os 5 botões de ação abrem o link certo (Ice original, licença, código, créditos).
3. Organização no Air M4: a nota "N itens ficam atrás do notch" aparece só quando há item preso; esvazie uma seção (ou use "Sempre escondida") e veja o convite.
4. Busca (atalho configurado): contagem, filtro sem resultado, setas e Return.

## Prints
`prints/` (tema escuro, app em inglês; o tema claro exige trocar a aparência do sistema, não feito). A Busca depende de atalho configurado e não foi capturada.
