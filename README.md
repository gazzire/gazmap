# GAZMAP 🥾

**POWERED BY GAZIRE**

**App de trilhas livre, gratuito e offline.** Grave caminhadas, trilhas, corridas e pedais com GPS, mesmo sem sinal de celular.

> Sem assinatura, sem anúncios, sem conta obrigatória. Seus dados ficam no seu celular.
> Licença GPL v3: qualquer pessoa pode usar, estudar, modificar e compartilhar, e as melhorias continuam abertas.

## Por que o GAZMAP existe

Os apps populares de atividade física vêm movendo recursos que eram gratuitos (como mapa offline, retrospectiva anual e rankings) para trás de assinaturas. O GAZMAP faz o caminho contrário: o essencial é grátis para sempre, e o código é da comunidade.

## Recursos (v0.1)

- 🎯 **Quatro atividades:** Trilha, Caminhada, Corrida e Bike, cada uma com sua métrica (ritmo em min/km ou velocidade em km/h)
- 📡 **GPS em segundo plano** com a tela apagada e o celular no bolso
- 📊 Distância, tempo em movimento, ritmo, velocidade, subida e descida
- ⏸️ Pausa manual e automática; **"segure para finalizar"** evita toques acidentais
- 🔊 **Avisos por voz** a cada quilômetro
- 🗺️ **Mapas offline grátis:** busque o lugar pelo nome (ex.: "Serra do Cipó"), ajuste a área e baixe
- 🏔️ Mapa topográfico com curvas de nível (OpenTopoMap) ou mapa de ruas (OpenStreetMap)
- 📈 Perfil de altimetria de cada atividade
- 📤 **Exportação GPX** (compatível com Strava, Wikiloc, Komoot e Garmin)
- 🛟 À prova de travamento: cada ponto é salvo na hora e a atividade é recuperada se o app fechar

Veja o que vem depois no [ROADMAP](ROADMAP.md).

## Instalar (Android)

1. Abra a aba [Releases](https://github.com/gazzire/gazmap/releases) e baixe `gazmap.apk`
2. No celular, permita "instalar apps de fontes desconhecidas"
3. Abra o GAZMAP e permita a localização

**Dica:** se a gravação parar com a tela apagada, desative a otimização de bateria para o GAZMAP (Configurações → Apps → GAZMAP → Bateria → Sem restrições).

## Desenvolver

Requisitos: [Flutter 3.24+](https://docs.flutter.dev/get-started/install) e JDK 17.

```bash
git clone https://github.com/gazzire/gazmap.git
cd gazmap
bash tool/setup_android.sh   # gera a pasta android/ com as permissões
flutter pub get
flutter test
flutter run
```

A cada push, o GitHub Actions compila o APK. Ao criar uma tag `v*`, o APK é publicado em Releases.

### Arquitetura

```
lib/
├── main.dart                 # inicialização e tema
├── models/                   # Track, TrackPoint, cálculos de estatística
├── services/
│   ├── recorder.dart         # GPS, estatísticas ao vivo, voz
│   ├── database.dart         # SQLite local
│   ├── tile_cache.dart       # cache de mapas e download de áreas
│   ├── place_search.dart     # busca de lugares (Nominatim/OSM)
│   ├── gpx.dart              # exportação GPX
│   └── settings.dart         # preferências
├── screens/                  # telas
└── widgets/                  # mapa base, estatísticas, altimetria
```

Decisões principais:
- **Offline-first:** SQLite local; nenhum servidor é necessário
- **Estatísticas confiáveis:** filtro de precisão do GPS, descarte de saltos impossíveis e histerese na altitude (evita a "subida fantasma")
- **Sem dependências pesadas:** estado com `ChangeNotifier`, gráficos com `CustomPainter`

## Contribuir

Contribuições são muito bem-vindas! Leia o [CONTRIBUTING](CONTRIBUTING.md).

## Créditos

- Dados de mapa © [colaboradores do OpenStreetMap](https://www.openstreetmap.org/copyright)
- Mapa topográfico © [OpenTopoMap](https://opentopomap.org) (CC-BY-SA)
- Busca de lugares: [Nominatim](https://nominatim.org)

Os servidores gratuitos de mapas têm limites de uso. O GAZMAP limita o tamanho de cada download e se identifica corretamente. Para uso intenso, configure seu próprio servidor de mapas em **Ajustes → Servidor próprio**.

## Licença

[GPL v3](LICENSE) © André Gazire e colaboradores. **POWERED BY GAZIRE.**

Termo adicional (GPL v3, seção 7b): versões modificadas devem preservar a atribuição "POWERED BY GAZIRE" no app e na documentação. Detalhes no arquivo [NOTICE](NOTICE).
