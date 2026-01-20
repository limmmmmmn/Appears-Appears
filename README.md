# HyperQuest 필드 시스템

## 📁 파일 구조

```
hyperquest_full/
├── data/
│   └── stages.json          # 스테이지/필드/적 풀 데이터
├── scripts/
│   ├── autoload/
│   │   └── FieldManager.gd  # 필드 스폰 & 전투 생성 (★ autoload 등록 필요!)
│   └── field/
│       ├── FieldController.gd  # 필드 씬 총괄
│       ├── FieldEnemy.gd       # 필드 적 (배회/추적/접촉)
│       ├── PartyLeader.gd      # 파티 리더 (플레이어 조작)
│       ├── PartyFollower.gd    # 파티 팔로워 (Snake 이동)
│       └── FieldTestMain.gd    # 테스트용
├── scenes/
│   └── field/
│       ├── FieldEnemy.tscn
│       ├── PartyLeader.tscn
│       ├── PartyFollower.tscn
│       ├── Field_Test.tscn
│       └── FieldTestMain.tscn  # 테스트 진입점
└── assets/
    └── sprites/
        └── placeholder_info.txt
```

## ⚙️ 설정 방법

### 1. AutoLoad 등록
프로젝트 설정 > AutoLoad에 추가:
- `FieldManager` → `res://scripts/autoload/FieldManager.gd`

### 2. 기존 AutoLoad 확인
이미 있어야 하는 autoload:
- `DataManager`
- `GameManager`
- `PartyManager`
- `BattleManager`

### 3. Collision Layer 설정
프로젝트 설정 > Layer Names > 2D Physics:
- Layer 1: default
- Layer 2: party
- Layer 3: (비어있음)
- Layer 4: enemy

### 4. 입력 액션 확인
프로젝트 설정 > Input Map:
- `ui_left`, `ui_right`, `ui_up`, `ui_down` (기본 있음)
- `ui_cancel` (ESC)

## 🎮 테스트 방법

1. `FieldTestMain.tscn`을 메인 씬으로 설정
2. F5로 실행
3. 방향키로 이동

## 📋 핵심 로직

### 타일 기반 적 스폰
- 타일맵의 타일 종류에 따라 적 풀 결정
- `stages.json`의 `terrain_enemies`에서 가중치 적용

### 전투 생성 규칙
- 필드 에너미 접촉 시 1~3마리 전투
- **필드 에너미가 최다 또는 동률** 유지
- 추가 적 선택 시 가중치 1.5제곱 적용

### 예시:
```
필드 적: 슬라임 (grass 타일에서)
전투 가능 조합:
  ✅ [슬라임]
  ✅ [슬라임, 박쥐]
  ✅ [슬라임, 슬라임, 고블린]
  ❌ [슬라임, 박쥐, 박쥐]  ← 박쥐가 더 많음!
```

## 🔜 다음 단계

1. [ ] 타일맵 에셋 추가 & tile_type_map 설정
2. [ ] 스프라이트 에셋 추가
3. [ ] BattleWindow 연결
4. [ ] 출구 → 마을/다음 스테이지 전환
