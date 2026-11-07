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

O requisito nunca é removido. Além disso, o helper é um XPC service embutido no app, só visível para o app que o contém.

**Pendente de validação em runtime** (precisa do Paulo, pois o Ice ainda está aberto e as permissões pedem confirmação): confirmar no Tahoe que o Menu Bar Layout carrega os itens com o requisito `signing-identifier`.
