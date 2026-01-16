# HyperQuest - 필드 시스템 프로토타입

## 프로젝트 구조

```
hyperquest/
├── project.godot          # Godot 프로젝트 설정
├── autoload/
│   ├── data_manager.gd    # JSON 데이터 로더
│   └── game_manager.gd    # 게임 상태 관리
├── data/
│   ├── heroes.json        # 영웅 데이터
│   ├── enemies.json       # 적 데이터
│   └── skills.json        # 스킬 데이터
├── scenes/
│   ├── field/
│   │   └── field.tscn     # 메인 필드 씬 (시작 씬)
│   ├── player/
│   │   └── player.tscn    # 플레이어 씬
│   ├── enemy/
│   │   └── field_enemy.tscn  # 필드 적 씬
│   └── ui/
│       └── battle_window.tscn  # 전투창 UI
└── scripts/
    ├── player.gd          # 플레이어 이동
    ├── field_enemy.gd     # 필드 적 AI
    ├── enemy_spawner.gd   # 적 스폰 시스템
    ├── battle_window.gd   # 전투 로직
    └── battle_manager.gd  # 다중 전투창 관리
```

## Godot에서 해야 할 작업

### 1. 프로젝트 열기
- Godot 4.3+에서 project.godot 파일 열기

### 2. 콜리전 셰이프 추가 (필수!)

**Player 씬 (scenes/player/player.tscn):**
1. CollisionShape2D 선택
2. Inspector > Shape > New RectangleShape2D
3. 크기: 14x14 정도

4. Hitbox/HitboxShape 선택
5. Inspector > Shape > New RectangleShape2D
6. 크기: 16x16 (살짝 크게)

**FieldEnemy 씬 (scenes/enemy/field_enemy.tscn):**
1. CollisionShape2D 선택
2. Shape > New RectangleShape2D
3. 크기: 14x14

4. Hitbox/HitboxShape 선택
5. Shape > New RectangleShape2D
6. 크기: 16x16

### 3. 스프라이트 설정 (선택)
- Player와 FieldEnemy의 Sprite2D에 텍스처 할당
- 없어도 동작은 함 (투명하게 보임)

### 4. TileMap 설정 (선택)
- Field 씬의 TileMap에 타일셋 할당
- 배경 타일 그리기

### 5. 실행
- F5로 실행
- WASD 또는 방향키로 이동
- 3초마다 카메라 바깥에서 적 스폰
- 적과 충돌하면 전투창 팝업
- 전투 중에도 이동 가능
- 전투창 여러 개 동시 가능

## 핵심 동작

1. **플레이어 이동**: 드퀘 스타일 8방향 이동
2. **적 스폰**: 카메라 바깥에서 생성 (뱀서 방식)
3. **적 서성임**: 스폰 위치 기준 제한된 범위만 이동
4. **전투 진입**: 플레이어-적 충돌 시 필드 적 사라지고 전투창 팝업
5. **자동 전투**: 쿨다운 기반, 양측 자동 공격
6. **동시 진행**: 전투 중에도 필드 이동 가능, 다중 전투 가능

## 레이어 설정 (project.godot에 포함됨)

- Layer 1: player
- Layer 2: enemy  
- Layer 3: world

## 다음 단계

- [ ] 스프라이트/애니메이션 추가
- [ ] 스탯 시스템 확장
- [ ] 더 많은 스킬 추가
- [ ] 전투창 UI 개선 (드퀘3 스타일)
- [ ] 맵 노드 시스템
