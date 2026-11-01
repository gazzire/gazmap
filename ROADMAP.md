# GAZMAP — Roadmap

**POWERED BY GAZIRE** · Site oficial: [gazire.com.br/gazmap](https://www.gazire.com.br/gazmap)

App de trilhas **livre (GPL v3), gratuito e offline-first**, para Android, com iPhone no futuro.

---

## Decisões do projeto

| Tema | Decisão |
|---|---|
| Nome | **GAZMAP** |
| Atribuição | **"POWERED BY GAZIRE"**, obrigatória em qualquer versão (termo adicional da GPL v3, seção 7b, no arquivo NOTICE) |
| Licença | GPL v3: qualquer pessoa pode usar, estudar, melhorar e compartilhar, e as melhorias continuam abertas |
| Público | Uso pessoal, gratuito para sempre, aberto à comunidade no GitHub |
| Prioridade | **A experiência de uso vem primeiro**, mesmo que dê mais trabalho construir |
| Plataforma | Android primeiro; iPhone depois, com o mesmo código |
| Tecnologia | Flutter + flutter_map + SQLite local |
| Mapas | OpenStreetMap / OpenTopoMap, com cache offline; servidor próprio opcional |
| Servidor | Opcional. O Hostinger do projeto pode hospedar mapas, sincronização e localização ao vivo |
| Site oficial | gazire.com.br/gazmap (página Elementor no WordPress) |
| Distribuição | APK compilado pelo GitHub Actions e publicado em Releases, sem loja de apps |

---

## Princípios (nascidos das reclamações dos usuários de Strava, AllTrails, Komoot e similares)

| Reclamação recorrente | Compromisso do GAZMAP |
|---|---|
| Recursos gratuitos movidos para trás de assinatura | **Nada pago, nunca.** O que é livre continua livre (garantido pela GPL) |
| Mapa offline bloqueado, descoberto só quando o sinal já sumiu | Download de mapas **grátis e explícito antes de sair** |
| Bateria acabando no meio da trilha | Modo economia de GPS, aviso de bateria baixa e mesh opcional |
| GPS "pulando" e inflando a distância | Filtros de precisão, de saltos e de ruído de altitude; passos como reserva |
| Atividades que não salvam ou somem | Cada ponto salvo na hora; recuperação automática após travamento |
| Seus dados presos na plataforma | Seus dados são seus: GPX sempre disponível, sem conta obrigatória |
| Privacidade (perfil público por padrão) | 100% local por padrão; compartilhamento só por escolha explícita |
| Retrospectiva anual cobrada | Estatísticas e retrospectiva **grátis** |

---

## v0.1 — Gravação e mapas offline ✅ (publicada em 01/11/2026)

- **Escolha da atividade:** Trilha, Caminhada, Corrida e Bike, cada uma com limiar de movimento e métrica própria (ritmo em min/km ou velocidade em km/h)
- GPS em segundo plano com notificação fixa, funcionando com a tela apagada
- Distância, tempo em movimento, tempo total, ritmo/velocidade, subida e descida
- Pausa manual e automática; **"segure para finalizar"** evita toque acidental no bolso
- **Avisos por voz configuráveis:** por distância (500 m, 1, 2, 5, 10, 15 ou 20 km) ou por tempo (5, 10, 15, 30 ou 60 min), escolhendo o que é falado: distância, tempo, ritmo/velocidade e subida
- Indicador de qualidade do GPS
- Histórico com resumo do mês, tela de detalhes, perfil de altimetria e exportação GPX
- **Escolha do lugar a baixar:** busca pelo nome (ex.: "Serra do Cipó") ou ajuste no mapa, com nível de detalhe
- Mapa topográfico (curvas de nível), mapa de ruas ou servidor próprio
- Recuperação automática da atividade se o app fechar

**Status:** compilada pelo GitHub Actions e publicada em [Releases](https://github.com/gazzire/gazmap/releases/tag/v0.1.0). Próximo passo: instalar e testar em uma trilha real.

---

## v0.2 — Segurança + passos

### 🆘 Botão SOS por SMS
- Segurar 3 segundos, seguido de uma contagem de 5 segundos cancelável (evita disparo no bolso)
- SMS automático para até 5 contatos de emergência, com:
  - coordenadas em graus decimais e precisão
  - link de mapa e horário
  - nível de bateria
- **Reenvio a cada 10 minutos** com a posição atualizada, até cancelar
- Funciona **sem internet** (basta sinal fraco de celular); sem nenhum sinal, a mensagem fica na fila e sai quando o sinal voltar
- Tela de SOS com as coordenadas em letras grandes e atalhos para **193 (Bombeiros), 192 (SAMU) e 190 (Polícia)**
- SMS de "alarme cancelado, está tudo bem" para evitar o cansaço dos contatos com alarme falso
- Atalho para o SOS por satélite do próprio celular, quando o aparelho tiver
- Android: envio automático (o app é instalado direto, fora da loja). iPhone: a mensagem abre pronta e é só tocar em enviar

### 🗺️ Plano de trilha (alerta automático de atraso)
- Antes de sair: trilha e horário previsto de volta
- Os contatos recebem: "André começou a trilha X, volta prevista às 17h"
- Se você não finalizar até o horário mais uma margem, o app pergunta "Você está bem?"; sem resposta, avisa os contatos com a última posição

### 🔋 Última posição antes da bateria acabar
- Com 15% de bateria, envia sozinho um SMS com a posição atual

### 🌅 Alerta de pôr do sol
- Calcula o pôr do sol offline e avisa: "Escurece em 1h30, e voltar pelo mesmo caminho leva cerca de 1h40"

### ✅ SMS de teste
- Confirma que os números estão certos e que a operadora entrega

### 👣 Contador de passos
- Passos também como opção nos avisos por voz
- Passos, cadência (passos/min) e comprimento médio da passada
- Usa o sensor de passos do celular: offline e com baixo consumo de bateria
- **Reserva quando o GPS falha** (vale fechado, mata densa) e pausa automática mais precisa
- Ativo em Trilha, Caminhada e Corrida; desligado em Bike

---

## v0.3 — Melhor Volta + orientação

### 🏆 Melhor Volta (recordes pessoais)
- **Reconhecimento automático** de trilhas repetidas (mesmo início, mesmo fim e caminho parecido)
- Melhor tempo, média, última vez e medalhas (🥇🥈🥉)
- **Corrida contra você mesmo ao vivo:** um "fantasma" do seu recorde no mapa, com "+1:20 atrás" ou "-0:45 à frente", também como opção nos avisos por voz
- **Trechos favoritos** com recorde próprio (ex.: "a subida do mirante")
- Recordes separados por atividade
- **Só os seus próprios dados, tudo local**, sem rankings entre pessoas

### ↩️ Voltar por onde vim
- Seta que guia pelo caminho já gravado, sem internet

### 🔦 Sinal para resgate
- A tela pisca e o alto-falante toca o padrão SOS (3 curtos, 3 longos, 3 curtos)

### 🪪 Ficha de emergência
- Tipo sanguíneo, alergias, remédios e contato visíveis na tela de SOS; ficam só no celular

### 🧭 Navegação por rota
- Importar GPX (Wikiloc, Komoot, amigos) e seguir a rota com alerta de **fora da rota** por vibração e voz
- Distância e subida restantes, e estimativa de chegada

### ⏸️ Detecção de imobilidade
- Parado tempo demais no meio da trilha: "Você está bem?" e, sem resposta, SOS automático

---

## v0.4 — Compartilhamento ao vivo

- **Localização ao vivo** por link (ex.: gazire.com.br/gazmap/ao-vivo/abc123), usando o Hostinger, sem custo extra
- Sem internet: o link mostra a última posição, e o app retoma o envio quando o sinal volta
- O link expira ao fim da atividade
- **WhatsApp junto com o SMS** quando houver internet

---

## v0.5 — Modo Grupo (rede mesh e P2P)

- **P2P local por Bluetooth e Wi-Fi Direct** (Google Nearby Connections), sem internet
- **Mesh pelos celulares:** mensagens e posições "pulam" de aparelho em aparelho
- **Integração com Meshtastic** (rádio LoRa barato, alcance de quilômetros, também código aberto GPL)
- Recursos:
  - grupo no mapa em tempo real, sem internet
  - alerta de separação: "Fulano está 300 m para trás"
  - mensagens rápidas offline: "Esperem", "Parada para água"
  - **SOS que viaja pelo grupo** até quem tiver sinal, que envia o SMS por você
- Limitações conhecidas: precisa de outras pessoas com o app (ou de um rádio LoRa); alcance menor em mata fechada; consome bateria (modo ligado só em grupo); conexão entre Android e iPhone limitada

---

## Depois (sem data)

- **Mapas offline melhores:**
  - mapas vetoriais (menores e nítidos em qualquer zoom)
  - pacotes prontos por estado hospedados no Hostinger
  - desenhar a área livremente ou baixar o entorno de uma rota GPX
  - aviso "você está sem mapa offline para esta área"
- **Pontos marcados:** nascente, mirante e bifurcação perigosa, com foto
- **Sincronização própria (opcional):** API mínima em PHP/MySQL no Hostinger, backup entre aparelhos e painel web
- **Importar a exportação oficial do Strava:** seus dados, por um caminho permitido
- **Estatísticas:** retrospectiva anual grátis e mapa de calor pessoal
- **iPhone:** mesmo código Flutter. Exige Mac ou Sideloadly; sem a assinatura de US$ 99/ano da Apple, o app expira a cada 7 dias
- Traduções e contribuições da comunidade

---

## Ideias descartadas

- **Calorias e hidratação:** retiradas do plano por decisão do André
- **Detecção de queda por acelerômetro:** muitos alarmes falsos e gasto de bateria; a detecção de imobilidade cobre o caso de forma mais confiável

## Fora do escopo (decisões conscientes)

- **Engenharia reversa da API privada do Strava:** viola os termos de uso, expõe o repositório a remoção e não é necessária. Os algoritmos (distância, altimetria, ritmo) são conhecimento público e foram implementados do zero
- **Rankings entre pessoas e segmentos ao estilo Strava:** exigem servidor central e têm risco de patente. Os recordes do GAZMAP são só pessoais e locais
- Anúncios, rastreamento de usuários e conta obrigatória
