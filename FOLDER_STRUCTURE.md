# HyperQuest 폴더 구조

Godot 프로젝트에서 아래 폴더들을 생성하세요.

```
HyperQuest/
│
├── project.godot          ← 프로젝트 설정 (제공됨)
├── icon.svg               ← 기본 아이콘 (Godot 기본)
│
├── data/                  ← 게임 데이터 (JSON)
│   ├── config.json        ← 게임 설정 (제공됨)
│   ├── characters.json    ← 캐릭터 데이터 (3단계)
│   ├── enemies.json       ← 적 데이터 (3단계)
│   ├── items.json         ← 아이템 데이터 (3단계)
│   ├── skills.json        ← 스킬 데이터 (3단계)
│   └── stages.json        ← 스테이지 데이터 (3단계)
│
├── scenes/                ← 씬 파일들
│   ├── Main.tscn          ← 메인 씬 (9단계)
│   ├── Field.tscn         ← 필드 씬 (7단계)
│   ├── WorldMap.tscn      ← 월드맵 씬 (8단계)
│   ├── Town.tscn          ← 마을 씬 (8단계)
│   │
│   ├── characters/        ← 캐릭터 씬
│   │   ├── Player.tscn
│   │   ├── PartyMember.tscn
│   │   └── FieldEnemy.tscn
│   │
│   ├── battle/            ← 전투 관련 씬
│   │   ├── BattleWindow.tscn
│   │   ├── EnemySlot.tscn
│   │   └── DamagePopup.tscn
│   │
│   └── ui/                ← UI 씬
│       ├── HUD.tscn
│       ├── TopBar.tscn
│       ├── PartyPanel.tscn
│       ├── Minimap.tscn
│       └── BattleLog.tscn
│
├── scripts/               ← 스크립트 파일들
│   ├── autoload/          ← 싱글톤 (Autoload)
│   │   ├── GameManager.gd
│   │   ├── DataManager.gd
│   │   ├── EventBus.gd
│   │   └── AudioManager.gd
│   │
│   ├── characters/        ← 캐릭터 스크립트
│   │   ├── Character.gd   ← 기본 클래스
│   │   ├── Player.gd
│   │   ├── PartyMember.gd
│   │   └── FieldEnemy.gd
│   │
│   ├── battle/            ← 전투 스크립트
│   │   ├── BattleManager.gd
│   │   ├── BattleWindow.gd
│   │   └── DamageCalculator.gd
│   │
│   ├── field/             ← 필드 스크립트
│   │   ├── FieldManager.gd
│   │   └── EnemySpawner.gd
│   │
│   ├── world/             ← 월드맵 스크립트
│   │   ├── WorldMapManager.gd
│   │   └── StageManager.gd
│   │
│   └── ui/                ← UI 스크립트
│       ├── HUD.gd
│       ├── TopBar.gd
│       ├── PartyPanel.gd
│       ├── Minimap.gd
│       └── BattleLog.gd
│
├── assets/                ← 리소스 파일들
│   ├── sprites/
│   │   ├── characters/    ← 캐릭터 스프라이트
│   │   ├── enemies/       ← 적 스프라이트
│   │   ├── tiles/         ← 타일 스프라이트
│   │   └── ui/            ← UI 스프라이트
│   │
│   ├── audio/
│   │   ├── bgm/           ← 배경음악
│   │   └── sfx/           ← 효과음
│   │
│   └── fonts/             ← 폰트 파일
│       └── pixel.ttf
│
└── resources/             ← Godot 리소스
    ├── themes/
    │   └── default_theme.tres
    └── tilesets/
        └── field_tileset.tres
```

## Godot에서 폴더 생성 방법

1. Godot 에디터 열기
2. FileSystem 패널에서 우클릭
3. "New Folder" 선택
4. 위 구조대로 폴더 생성

## 다음 단계

1단계 완료 후, 2단계에서 scripts/autoload/ 폴더의 스크립트들을 만듭니다.
