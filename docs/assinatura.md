# Assinatura e XPC

## Por que um certificado local

Sem Developer ID o app seria assinado ad hoc, e o cdhash muda a cada build: o macOS (TCC) esquece Acessibilidade e Gravação de Tela a cada instalação. Com o certificado autoassinado **Trincano Local Signing** o requisito designado fica
`identifier "br.com.pilutech.trincano" and certificate leaf = H"<hash>"`, que não muda entre builds.

- `scripts/signing.sh` cria o certificado na primeira build, num keychain próprio sem senha em `~/.trincano/signing/trincano-signing.keychain-db` (adicionado à lista de busca do usuário). Nada vai para o login keychain.
- Recriar o certificado muda o hash e **pede as permissões de novo**; não apague o keychain sem necessidade.
- O certificado não é confiável para o sistema (não passa no Gatekeeper para outros Macs). Serve só para uso local.

## Trocar pelo Developer ID (quando a aprovação sair)

```sh
SIGN_IDENTITY="Developer ID Application: Nome (TEAMID)" SIGN_KEYCHAIN="" scripts/build.sh
```

`SIGN_KEYCHAIN=""` usa os keychains normais. Para distribuir fora do Mac será preciso notarizar (`notarytool`), o que não faz parte da fase 1. Com Team ID a checagem do XPC volta sozinha para "mesmo time".

## Checagem do canal XPC (app ↔ MenuBarItemService)

`.isFromSameTeam()` nunca passa sem Team ID. Em vez de desligar a checagem (como fazem os PRs #950/#982/#1027 do upstream), o Trincano escolhe por `XPCPeerPolicy` (`Shared/Utilities/XPCPeerPolicy.swift`, com testes):

| Build | Requisito do peer |
|---|---|
| Com Team ID (Developer ID / Apple Development) | mesmo time **e** signing identifier esperado |
| Sem Team ID (certificado local ou ad hoc) | signing identifier exato (requisito leve `signing-identifier`) |

**Limite conhecido (MÉDIO, em aberto):** o `signing-identifier` sozinho **não prova que o peer foi assinado com o nosso certificado**. Verificado offline: copiar o `.xpc`, reassinar ad hoc (`codesign -f -s -`) mantém `identifier "…MenuBarItemService"` satisfeito, mas **falha** em `identifier "…" and certificate leaf = H"…"`. A API Swift `XPCPeerRequirement` do SDK 26 não aceita string de requisito nem certificado (só entitlement, mesmo time, plataforma e requisitos leves), e `XPCSession`/`XPCListener` não expõem o handle C para `xpc_*_set_peer_code_signing_requirement`. Prender o certificado exigiria trocar o transporte XPC por conexão C ou usar `cdhash`; fica como tarefa própria.
Mitigação atual: o helper é um XPC service embutido no app, visível só ao app que o contém, e a checagem continua ativa (melhor que os PRs do upstream, que a removem). Com Developer ID o requisito volta a ser "mesmo time" e o limite some.

**Pendente de validação em runtime** (precisa do Paulo, pois o Ice ainda está aberto e as permissões pedem confirmação): confirmar no Tahoe que o Menu Bar Layout carrega os itens com o requisito `signing-identifier`.

## Chave de assinatura

O keychain `~/.trincano/signing` não tem senha nem bloqueio automático e está na lista de busca: qualquer processo rodando como o usuário pode assinar como "Trincano Local Signing". Aceito para um certificado local sem valor fora deste Mac; o Developer ID **não** deve seguir esse modelo (usar o login keychain/Secure Enclave).

## Ferramentas (versões)

SwiftLint 0.65.1 (MIT, Homebrew); gem `xcodeproj` 1.28.1 (MIT) e dependências instaladas com ela (nanaimo, colored2, claide, atomos, base64, nkf, CFPropertyList), só em `~/.gem` do usuário, usadas apenas por `scripts/add-test-target.rb` (dev, nunca embutidas no app).
