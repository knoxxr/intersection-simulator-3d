# 3D 교차로 교통 시뮬레이터 (Godot 4.3 + Vercel Web Export)

Godot 4.3으로 개발된 3D 교차로 교통 흐름 시뮬레이터입니다. 데스크톱(Godot 4.3)과 웹(HTML5/WebAssembly, Vercel 정적 배포) 모두에서 실행됩니다.

## 주요 기능

- **실시간 차선 제어**: 편도 1~3차선 실시간 변경, 개별 차선 개방/폐쇄(폐쇄 시 도로 라바콘 자동 배치), 북/남/동/서 진입 방향 개별 활성/비활성
- **실시간 교통량 & 회전 비율**: 전체 교통량 배율(0.0x~3.0x), 방향별 통행량(북/남/동/서), 좌회전/우회전 비율 실시간 조절
- **다양한 신호등 시나리오**:
  - `2현시 (남북/동서 교대)`
  - `4현시 (좌회전 보호 신호)`
  - `황색 점멸 (주의 서행 및 양보)`
  - `전체 적색 (긴급 정지 / 정체 테스트)`
  - 남북 녹색 / 동서 녹색 / 좌회전 보호 / 황색 신호 시간 실시간 조절 및 즉시 전환
- **실시간 현황 대시보드**: 현재 신호 상태 및 남은 시간, 주행 중/대기 중 차량 수, 누적 통과 대수, 분당 처리량, 평균 대기 시간
- **3D 카메라 & 터치 제어**: 데스크톱(마우스 드래그/휠), 모바일(한 손가락 회전, 두 손가락 핀치 줌, 줌/시점 전환 퀵 버튼)
- **모바일 반응형 UI**: 세로/소형 화면에서 상단 컴팩트 상태바, 하단 탭 시트(`차선`·`트래픽`·`신호등`·`제어`), DPI 자동 스케일링 및 터치 친화적 버튼/슬라이더 적용

## 실행 방법

### 1. Godot 4.3 데스크톱 실행
```bash
godot4 --path .
```

### 2. Web 빌드 생성 (HTML5/WASM)
```bash
godot4 --headless --path . --export-release "Web" web_build/index.html
```

### 3. Vercel 배포
`vercel.json`에 `outputDirectory: "web_build"`와 WASM/COOP/COEP 헤더가 설정되어 있습니다.

- **Vercel CLI**:
  ```bash
  npx vercel --prod
  ```
- **GitHub 연동 (원클릭 배포)**:
  - [Vercel에서 바로 Import하여 배포하기](https://vercel.com/new/import?s=https://github.com/knoxxr/intersection-simulator-3d)
  - 저장소: https://github.com/knoxxr/intersection-simulator-3d
