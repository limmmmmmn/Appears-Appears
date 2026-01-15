# Hyper Quest - Week 4 완성본 (MVP 완료!)

## 🎉 MVP 완성!

Week 4까지 모든 핵심 시스템이 완성되었습니다!

---

## 🆕 Week 4 새 기능

### 📊 HUD 시스템
- 💰 골드 표시
- 📈 레벨 & 경험치 바
- 💀 킬 카운트
- 🏰 현재 스테이지
- ⏱️ 플레이 시간
- ❤️ 파티 HP 바 (실시간!)
- ✨ 활성 시너지 표시

### 🏰 스테이지 시스템
- 20킬마다 보스 소환!
- 스테이지당 난이도 20% 증가
- 스폰 속도 증가
- 최대 10스테이지

### 👹 보스 시스템
- 일반 적보다 10배 강함
- 특수 공격 (전체 공격!)
- 보스 전용 전투창
- 무조건 Magic+ 아이템 드랍!

### 🎮 게임 오버 & 승리
- 파티 전멸 → 게임 오버
- 10스테이지 클리어 → 던전 클리어!
- 최종 기록 표시
- 재시작 / 종료 선택

### 💾 세이브/로드
- P 키로 세이브
- 파티, 인벤토리, 골드, 스테이지 저장
- 게임 시작 시 자동 로드

---

## 🎹 조작법

```
이동: WASD / 방향키
인벤토리: I
마을 입장: SPACE (노란 타일에서)
세이브: P
UI 닫기: ESC
```

---

## 📁 새 스크립트

```
scripts/autoload/
├─ StageManager.gd (스테이지 관리)
└─ SaveManager.gd (세이브/로드)

scripts/enemies/
└─ Boss.gd (보스 전용)

scripts/battle/
└─ BossBattleWindow.gd (보스 전투창)

scripts/ui/
├─ HUD.gd (실시간 상태 표시)
└─ GameOverUI.gd (게임오버/승리)
```

---

## 🛠️ 씬 만들기 가이드

### HUD.tscn
```
CanvasLayer (layer: 50)
└─ TopBar (HBoxContainer) - 화면 상단
   ├─ LevelLabel (Label): "Lv.1"
   ├─ ExpBar (ProgressBar): 150x20
   ├─ GoldLabel (Label): "💰 1000"
   ├─ KillLabel (Label): "💀 0"
   ├─ StageLabel (Label): "Stage 1"
   └─ TimerLabel (Label): "00:00"
└─ PartyHP (VBoxContainer) - 왼쪽 하단
└─ SynergyPanel (VBoxContainer) - 오른쪽

Script: res://scripts/ui/HUD.gd
저장: res://scenes/ui/HUD.tscn
```

### Boss.tscn
```
CharacterBody2D (이름: Boss)
├─ Sprite2D (보라색, 64x64)
├─ CollisionShape2D (Circle, Radius: 32)
└─ Hitbox (Area2D)
   └─ CollisionShape2D (Circle, Radius: 40)

Group: enemies
Script: res://scripts/enemies/Boss.gd
저장: res://scenes/enemies/Boss.tscn
```

### BossBattleWindow.tscn
```
Panel (500 x 400)
└─ VBoxContainer
   ├─ BossName (Label): "👹 BOSS 👹"
   ├─ BossHP (ProgressBar): 빨간색
   ├─ BossHPText (Label): "500/500"
   ├─ HSeparator
   ├─ PartyList (VBoxContainer)
   └─ BattleLog (TextEdit): 읽기 전용, 스크롤

Script: res://scripts/battle/BossBattleWindow.gd
저장: res://scenes/ui/BossBattleWindow.tscn
```

### GameOverUI.tscn
```
Panel (400 x 400)
└─ VBoxContainer
   ├─ Title (Label): "GAME OVER"
   ├─ Stats (Label): 여러 줄 텍스트
   ├─ RestartButton (Button): "다시 시작"
   └─ QuitButton (Button): "종료"

Script: res://scripts/ui/GameOverUI.gd
저장: res://scenes/ui/GameOverUI.tscn
```

---

## 🎮 게임 흐름

```
1. 게임 시작
   ├─ HUD 표시
   └─ 적 스폰 시작

2. 전투
   ├─ 적 처치 → 킬 카운트 증가
   ├─ 아이템 드랍 → 3지선다
   └─ 경험치 → 레벨업

3. 보스 등장 (20킬)
   ├─ 일반 적 제거
   ├─ 보스 스폰!
   └─ 보스 전투창 (더 큼)

4. 보스 처치
   ├─ Magic+ 아이템 드랍!
   ├─ 스테이지 클리어
   └─ 다음 스테이지 (난이도 ↑)

5. 10스테이지 클리어
   └─ 🎉 던전 클리어!

6. 파티 전멸
   └─ 💀 게임 오버
```

---

## ✅ 전체 체크리스트

### 기존 씬 (Week 2-3):
```
□ Player.tscn
□ Enemy.tscn
□ BattleWindow.tscn
□ TestField.tscn
□ ItemChoiceUI.tscn
□ InventoryUI.tscn
□ TownUI.tscn
□ TavernUI.tscn
□ ShopUI.tscn
□ ChurchUI.tscn
```

### 새 씬 (Week 4):
```
□ HUD.tscn
□ Boss.tscn
□ BossBattleWindow.tscn
□ GameOverUI.tscn
```

---

## 🎯 게임 완성 확인

```
✅ 플레이어 이동
✅ 적 스폰 (뱀서 스타일)
✅ 전투 시스템 (ATB)
✅ 아이템 3지선다
✅ 인벤토리 & 장비
✅ 마을 시스템
✅ 영웅 영입/해고
✅ 상점 구매/판매
✅ 부활/회복
✅ HUD (실시간 정보)
✅ 스테이지 진행
✅ 보스전
✅ 게임 오버/승리
✅ 세이브/로드

→ MVP 완성! 🎉
```

---

## 🚀 다음 단계 (확장)

```
□ 추가 챕터
□ 새로운 영웅
□ 더 많은 아이템
□ 스킬 시스템
□ 이벤트 노드
□ 음악 & 효과음
□ 그래픽 에셋
□ 밸런스 조정
```

---

## 💡 팁

**보스 난이도 조절:**
```gdscript
# StageManager.gd에서
kills_for_boss = 10  # 10킬마다 보스 (쉽게)
```

**스테이지 배율 조절:**
```gdscript
# StageManager.gd에서
stage_enemy_multiplier = 1.0 + (current_stage - 1) * 0.1  # 10%씩 증가
```

**세이브 위치:**
```
Windows: %APPDATA%\Godot\app_userdata\HyperQuest\
macOS: ~/Library/Application Support/Godot/app_userdata/HyperQuest/
Linux: ~/.local/share/godot/app_userdata/HyperQuest/
```

---

🎉 **축하합니다! Hyper Quest MVP 완성!** 🎉
