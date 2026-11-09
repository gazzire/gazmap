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
| Plataforma | Android (iPhone pausado) |
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

## v0.1 — Gravação e mapas offline ✅ (01/11/2026)

Gravação com GPS em segundo plano, 4 atividades, avisos por voz configuráveis, histórico, altimetria, mapas offline com busca de lugar.

## v0.2 — Versão completa ✅ (09/11/2026)

Entregue numa única versão (antes planejado como v0.2 a v0.5):

### 🆘 Segurança (100% offline, via SMS)
- SOS: segurar 3 s + contagem de 5 s; SMS para até 5 contatos com coordenadas, link de mapa e bateria; reenvio a cada 5–30 min; fila automática sem sinal; "alarme cancelado"
- Tela de SOS com coordenadas grandes, 193/192/190, WhatsApp (opcional), sinal de resgate (lanterna + bipe + tela em Morse SOS) e ficha de emergência
- Plano de trilha com horário de volta e alerta automático de atraso
- "Você está bem?" por imobilidade ou atraso, com SOS automático sem resposta
- Aviso de bateria em 15% com a última posição; alerta de pôr do sol calculado offline; SMS de teste

### 👣 Passos
- Contador de passos, cadência e passada; estimativa de distância pelos passos quando o GPS falha; passos no aviso por voz

### 🗺️ Mapas e navegação
- Pacote Minas Gerais (visão geral, zoom até 11, ~100 MB); download do entorno de uma rota; aviso de "sem mapa offline"
- Navegação por rota com alerta de fora da rota, distância e subida restantes e hora de chegada; voltar por onde vim

### 📁 Arquivos
- Importar e exportar **GPX, TCX e FIT** (atividades e rotas); importa o export do Strava (.fit.gz)

### 🥇 Melhor Volta
- Reconhecimento de trilhas repetidas, recorde, média, medalhas, comparação com a última vez
- Corrida contra o "fantasma" do recorde, com aviso por voz; trechos favoritos com recordes

### 👥 Modo Grupo (sem internet) + gamificação
- Grupo com nome, vários grupos na mesma trilha; mesh de até 6 saltos (Nearby Connections)
- Membros no mapa, alerta de separação (300 m / 10 min), mensagens rápidas
- **Gamificação:** pontos GAZ (km, subida, passos), ranking ao vivo, pódio de chegada
- SOS que atravessa todos os grupos e é retransmitido por SMS por quem tiver sinal

### 📊 Extras
- Pontos marcados com foto; retrospectiva do ano; mapa de calor; 10 conquistas pessoais

### 🌐 Opcional com internet
- Localização ao vivo por link (gazire.com.br/gazmap/ao-vivo/...), expira ao terminar

## Próximos passos

- **Teste real em trilha** e ajustes a partir do uso
- **Meshtastic (rádio LoRa):** quando houver um rádio para testar
- **Pausado por enquanto:** versão para iPhone e assinatura fixa do app (por ora, desinstale antes de atualizar)
- Mapas vetoriais (exigem outro motor de mapa e servidor próprio de mapas)

## Ideias descartadas

- **Calorias e hidratação:** retiradas do plano por decisão do André
- **Traduções:** o app é só em português
- **Pacotes de mapa detalhado por estado:** Minas Gerais inteiro no zoom de trilha passa de 6 GB; o detalhe é baixado por área ou rota
- **Detecção de queda por acelerômetro:** muitos alarmes falsos e gasto de bateria; a detecção de imobilidade cobre o caso de forma mais confiável

## Fora do escopo (decisões conscientes)

- **Engenharia reversa da API privada do Strava:** viola os termos de uso, expõe o repositório a remoção e não é necessária. Os algoritmos (distância, altimetria, ritmo) são conhecimento público e foram implementados do zero
- **Rankings entre pessoas e segmentos ao estilo Strava:** exigem servidor central e têm risco de patente. Os recordes do GAZMAP são só pessoais e locais
- Anúncios, rastreamento de usuários e conta obrigatória
