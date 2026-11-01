# GAZMAP — Roadmap

**POWERED BY GAZIRE**

App de trilhas **livre (GPL v3), gratuito e offline-first**.

## Princípios (nascidos das reclamações dos usuários de Strava, AllTrails, Komoot e similares)

| Reclamação recorrente | Compromisso do GAZMAP |
|---|---|
| Recursos gratuitos movidos para trás de assinatura | **Nada pago, nunca.** O que é livre continua livre (garantido pela GPL) |
| Mapa offline bloqueado, descoberto só quando o sinal já sumiu | Download de mapas **grátis e explícito antes de sair** |
| Bateria acabando no meio da trilha | Modo economia de GPS e estimativa de autonomia |
| GPS "pulando" e inflando a distância | Filtros de precisão, de saltos e de ruído de altitude |
| Atividades que não salvam ou somem | Cada ponto salvo na hora; recuperação automática após travamento |
| Seus dados presos na plataforma | Seus dados são seus: GPX sempre disponível, sem conta obrigatória |
| Privacidade (perfil público por padrão) | 100% local por padrão; sincronização só no seu próprio servidor |

## Fase 1 — MVP de gravação ✅ (v0.1)
- Escolha da atividade: **Trilha, Caminhada, Corrida, Bike** (cada uma com limiar de movimento e métrica própria: ritmo ou km/h)
- GPS em segundo plano com notificação fixa
- Distância, tempo em movimento, ritmo/velocidade, subida e descida
- Pausa manual e automática; "segure para finalizar" (evita toque acidental no bolso)
- Avisos por voz a cada km
- Histórico, detalhes, perfil de altimetria, exportação GPX
- Cache de mapa e download de área: **busca do lugar pelo nome** ou ajuste no mapa, com escolha do nível de detalhe

## Fase 2 — Mapas offline de verdade (v0.2)
- **Mais formas de escolher o lugar:**
  - Desenhar a área livremente ou baixar o entorno de uma rota GPX
  - Pacotes prontos por estado (arquivos PMTiles hospedados no servidor do projeto, por exemplo no Hostinger)
- Gerenciar áreas baixadas: tamanho, atualização e exclusão
- Mapas vetoriais (menores, nítidos em qualquer zoom), com estilo diferente por atividade: trilhas em destaque para caminhada, ciclovias e tipo de piso para bike
- Aviso antes de começar: "Você está sem mapa offline para esta área"

## Fase 3 — Navegação
- Importar GPX (Wikiloc, Komoot, amigos)
- Seguir a rota com alerta de **fora da rota** por vibração e voz
- Distância restante, subida restante e estimativa de chegada
- Ponto de retorno: "volte por onde veio"

## Fase 4 — Segurança na trilha
- Estimativa de bateria restante versus duração prevista
- SOS: envia sua coordenada por SMS (funciona sem internet)
- Compartilhamento de localização ao vivo (quando houver sinal)
- Marcar pontos: nascente, mirante, bifurcação perigosa (com foto)

## Fase 5 — Sincronização própria (opcional)
- API mínima em PHP/MySQL, instalável em qualquer hospedagem comum
- Backup e sincronização entre aparelhos
- Painel web com todas as atividades no mapa

## Fase 6 — iPhone e comunidade
- Versão iOS com o mesmo código (Flutter)
- Estatísticas anuais **grátis** (a "retrospectiva do ano")
- Mapa de calor pessoal de todos os lugares por onde você passou
- Traduções e contribuições da comunidade

## Fora do escopo (decisões conscientes)
- **Engenharia reversa da API privada do Strava:** viola os termos de uso, expõe o repositório a remoção e não é necessária. Os algoritmos (distância, altimetria, ritmo) são conhecimento público e foram implementados do zero aqui.
- **Rankings e segmentos ao estilo Strava:** exigem servidor central e têm risco de patente. Se um dia existirem, serão locais (seus próprios recordes por trecho).
- Anúncios e rastreamento de usuários.
