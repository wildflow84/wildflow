# polestar-auto-off

차량(Android Automotive)의 설정 화면을 접근성 서비스로 읽고, 지정한 옵션(차선 유지 보조, 속도 제한 경고)이 켜져 있으면 스위치를 눌러 끄는 앱.

**상태: 실차 검증 전.** 설정 메뉴의 실제 라벨과 구조를 모르는 상태로 만들었기 때문에, 첫 실행은 튜닝용이라고 보면 돼. 아래 "튜닝" 참고.

## 동작

1. 트리거: 접근성 서비스 연결, 화면 켜짐, 사용자 잠금 해제 시 (`cooldownSec` 안에 성공한 적 있으면 건너뜀).
2. `assets/script.json`의 스텝을 순서대로 실행. 화면에서 라벨을 찾고(없으면 스크롤), 스위치 상태를 읽어서 켜져 있을 때만 누름. 이미 꺼져 있으면 아무것도 안 함.
3. 스텝이 시간 초과되면 그 시점의 화면 구조를 로그에 남기고 최대 `maxAttempts`번 재시도.

한계:
- 차량이 시동 때 설정을 되돌리는 시점에 헤드유닛 화면이 꺼졌다 켜지지 않으면 트리거가 안 걸릴 수 있음.
- 차량이 일부 상황에서 차선 이탈 방지 개입을 하도록 만들어둔 부분은 설정을 꺼도 남음.
- 주행 중 화면 조작은 위험하고 차량이 막을 수도 있음. 정차 상태(시동 직후)에서 돌아가는 걸 전제로 함.

## 빌드

GitHub Actions(`.github/workflows/polestar-auto-off.yml`)가 푸시마다 디버그 APK를 만들어서 아티팩트 `polestar-auto-off-debug-apk`로 올림. 로컬 빌드는 Android SDK + Gradle 8.10+ 에서 `gradle assembleDebug`.

## 설치

차량에서 개발자 옵션/ADB 또는 사이드로딩이 되는 경우:

```
scripts/setup.sh app-debug.apk
```

APK 설치, `WRITE_SECURE_SETTINGS` 권한 부여, 접근성 서비스 활성화를 한 번에 함. 권한을 줘두면 앱이 부팅/업데이트 때 스스로 접근성 서비스를 다시 켬. ADB 없이 앱만 설치된 경우엔 앱의 "접근성 서비스 켜기" 버튼 후 시스템 접근성 설정에서 직접 켜야 함.

## 튜닝

1. 앱에서 "지금 실행"을 누르고 로그를 확인. 실패하면 로그에 그 시점의 화면 트리(`text=`, `desc=`, `[c k K s]` 플래그)가 찍힘. `K`는 켜진 스위치, `k`는 꺼진 스위치.
2. 대상 화면에서 직접 덤프하려면 "10초 뒤 현재 화면 덤프"를 누르고 그 화면으로 이동. ADB가 되면 `scripts/dump_ui.sh`도 가능.
3. `script.json`의 `any` 라벨을 실제 문구로 고침. 앱을 다시 빌드하지 않으려면 `/sdcard/Android/data/com.wildflow.polestarautooff/files/script.json`에 같은 형식으로 넣으면 그 파일이 우선.

스텝 종류: `open_settings`, `launch`(`pkg`), `click`(`any`), `set_off`(`any`), `back`, `home`, `wait`(`ms`). `optional: true`면 못 찾아도 건너뜀.

옵션이 스위치가 아니라 "끔/경고/보조" 같은 선택지라면 `set_off` 대신 `click`을 두 번(항목 → "끔") 쓰면 됨. 이 경우는 이미 꺼져 있어도 눌러서 문제는 없지만 불필요한 조작이 생김.
