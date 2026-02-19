# HyperQuest 필드 시스템

## 📁 구조

```
hyperquest_full/
├── data/
│   └── acts/                    # 액트 템플릿(.tres)
│
├── scripts/
│   ├── autoload/
│   │   └── FieldManager.gd      # ★ autoload 등록 필요!
│   ├── field/
│   │   ├── Field.gd             # 필드 씬 컨트롤러
│   │   ├── FieldEnemy.gd        # 필드 적 (배회/추적)
│   │   ├── PartyLeader.gd       # 플레이어 조작
│   │   └── PartyFollower.gd     # Snake 팔로우
│   ├── GameManager_Extension.gd # GameManager에 추가할 코드
│   └── town/
│       └── Town_Extension.gd    # Town.gd에 추가할 코드
│
└── scenes/
	└── field/
		├── PartyLeader.tscn
		├── PartyFollower.tscn
		├── FieldEnemy.tscn
		└── Field1_1.tscn       # 테스트 필드
```

## ⚙️ 설치 방법

### 1. 파일 복사
- `data/acts/*.tres` → 기존 data/acts 폴더에
- `scripts/autoload/FieldManager.gd` → 기존 autoload 폴더에
- `scripts/field/*` → 기존 scripts 폴더에 field 폴더 생성 후 복사
- `scenes/field/*` → 기존 scenes 폴더에 field 폴더 생성 후 복사

### 2. AutoLoad 등록
프로젝트 설정 > AutoLoad:
```
FieldManager → res://scripts/autoload/FieldManager.gd
```

### 3. GameManager 수정
`GameManager_Extension.gd` 내용을 기존 `GameManager.gd`에 추가

### 4. Town에서 출발 버튼 연결
`Town_Extension.gd` 참고해서 출발 버튼 추가

### 5. Collision Layer 설정 (이미 안되어있다면)
프로젝트 설정 > Layer Names > 2D Physics:
- Layer 2: party
- Layer 4: enemy

## 🎮 테스트

### Town에서 시작하는 경우
1. Town 씬에 "출발" 버튼 추가
2. 버튼 → `GameManager.go_to_area()` 호출

### Field 직접 테스트
1. `Field1_1.tscn`을 메인 씬으로 설정
2. 실행 전 FieldManager 초기화:
```gdscript
# Main.gd 또는 테스트 스크립트에서
func _ready():
	FieldManager.set_current_act("act_1")
	FieldManager.set_current_area(FieldManager.get_first_area_id("act_1"))
```

## 📋 핵심 로직

### 전투 생성 규칙
- 필드 적 접촉 → 1~3마리 전투
- **필드 적이 최다 또는 동률** 유지
- 가중치 1.5제곱 적용

### 예시
```
필드에서 슬라임 접촉 →
  ✅ [슬라임]
  ✅ [슬라임, 박쥐]
  ✅ [슬라임, 슬라임, 고블린]
  ❌ [슬라임, 박쥐, 박쥐]  ← 박쥐가 더 많아서 불가!
```

## 🔜 다음 단계

1. [ ] 전투창(BattleWindow) 구현
2. [ ] 전투 승리 → 필드 적 제거
3. [ ] 출구 → Town/다음 액트 전환
4. [ ] 스프라이트 에셋 추가
