# [ERR-001] adapter-static에서 동적 라우트 빌드 실패

## 요약
`@sveltejs/adapter-static`을 사용할 때, `prerender = false`로 설정된 라우트가 존재하면 Vercel 빌드가 실패한다.

## 근본 원인
`adapter-static`은 모든 라우트가 완전히 프리렌더링 가능해야 한다는 전제로 동작한다.
`/gallery/saved`는 localStorage 기반으로 SSR이 불가능해 `prerender = false` / `ssr = false`로 설정되어 있었으나, `svelte.config.js`에 `fallback` 옵션이 누락되어 어댑터가 동적 라우트를 발견하면 에러를 던졌다.

```
Error: Encountered dynamic routes
@sveltejs/adapter-static: all routes must be fully prerenderable,
but found the following routes that are dynamic:
  - src/routes/gallery/saved
```

## 재현 방법
1. `svelte.config.js`에서 `adapter({ fallback: '404.html' })` → `adapter()`로 변경
2. `npm run build` 실행
3. 빌드 시 위 에러 발생

## 해결책
`svelte.config.js`의 어댑터 설정에 `fallback` 옵션 추가:

```js
// 변경 전
adapter: adapter()

// 변경 후
adapter: adapter({ fallback: '404.html' })
```

`fallback` 옵션이 있으면 프리렌더링되지 않은 경로를 SPA 방식으로 처리하며, Vercel은 해당 fallback HTML을 자동으로 서빙한다.

## 예방 체크리스트
- [ ] `prerender = false`인 라우트가 있다면 `svelte.config.js`에 `fallback` 옵션이 설정되어 있는지 확인
- [ ] `ssr = false`인 페이지를 추가할 때마다 빌드 설정을 함께 검토
- [ ] Vercel 배포 전 로컬에서 `npm run build` 실행하여 어댑터 오류 사전 확인

## 관련 파일
- `svelte.config.js` — 어댑터 fallback 옵션
- `src/routes/gallery/saved/+page.ts` — `prerender = false`, `ssr = false` 설정
