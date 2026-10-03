const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-ourday',
    firestore: { rules: fs.readFileSync(require('path').join(__dirname, '../../firestore.rules'), 'utf8'), host: '127.0.0.1', port: 8085 },
  });
  const SP = 'spaceX';
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`spaces/${SP}`).set({ members: ['dad', 'mina'] });
    await db.doc(`spaces/${SP}/items/shared1`).set({ ownerUid: 'dad', visibility: 'shared', title: 'a', done: false });
    await db.doc(`spaces/${SP}/items/priv1`).set({ ownerUid: 'dad', visibility: 'private', title: 'p' });
  });
  const dad = env.authenticatedContext('dad').firestore();
  const mina = env.authenticatedContext('mina').firestore();
  const stranger = env.authenticatedContext('eve').firestore();
  const results = [];
  const t = async (name, fn) => { try { await fn(); results.push(['PASS', name]); } catch (e) { results.push(['FAIL', name, String(e.message).slice(0, 120)]); } };

  await t('상대가 같이보기 항목 읽기', () => assertSucceeds(mina.doc(`spaces/${SP}/items/shared1`).get()));
  await t('상대가 프라이빗 항목 읽기 차단', () => assertFails(mina.doc(`spaces/${SP}/items/priv1`).get()));
  await t('상대가 같이보기 항목 제목 수정 허용', () => assertSucceeds(mina.doc(`spaces/${SP}/items/shared1`).update({ title: 'b' })));
  await t('상대가 같이보기 항목 완료 체크 허용', () => assertSucceeds(mina.doc(`spaces/${SP}/items/shared1`).update({ done: true })));
  await t('상대가 공개범위를 private으로 바꾸기 차단', () => assertFails(mina.doc(`spaces/${SP}/items/shared1`).update({ visibility: 'private' })));
  await t('상대가 소유자 바꾸기 차단', () => assertFails(mina.doc(`spaces/${SP}/items/shared1`).update({ ownerUid: 'mina' })));
  await t('상대가 프라이빗 항목 수정 차단', () => assertFails(mina.doc(`spaces/${SP}/items/priv1`).update({ title: 'x' })));
  await t('상대가 같이보기 항목 삭제 차단(소유자만)', () => assertFails(mina.doc(`spaces/${SP}/items/shared1`).delete()));
  await t('소유자가 자기 항목 공개범위 변경 허용', () => assertSucceeds(dad.doc(`spaces/${SP}/items/shared1`).update({ visibility: 'private' })));
  await t('(변경 후) 상대가 이제 프라이빗이 된 항목 수정 차단', () => assertFails(mina.doc(`spaces/${SP}/items/shared1`).update({ title: 'z' })));
  await t('소유자가 삭제 허용', () => assertSucceeds(dad.doc(`spaces/${SP}/items/priv1`).delete()));
  await t('외부인이 같이보기 항목 읽기 차단', async () => {
    await env.withSecurityRulesDisabled(async (c) => c.firestore().doc(`spaces/${SP}/items/s2`).set({ ownerUid: 'dad', visibility: 'shared' }));
    await assertFails(stranger.doc(`spaces/${SP}/items/s2`).get());
  });
  await t('외부인이 같이보기 항목 수정 차단', () => assertFails(stranger.doc(`spaces/${SP}/items/s2`).update({ title: 'hack' })));
  await t('멤버가 카테고리 쓰기 허용', () => assertSucceeds(mina.doc(`spaces/${SP}/categories/c1`).set({ name: 'x' })));
  await t('외부인이 카테고리 쓰기 차단', () => assertFails(stranger.doc(`spaces/${SP}/categories/c1`).set({ name: 'x' })));
  await t('멤버가 휴일 추가 허용', () => assertSucceeds(dad.doc(`spaces/${SP}/holidays/h1`).set({ name: 'x' })));
  await t('외부인이 휴일 추가 차단', () => assertFails(stranger.doc(`spaces/${SP}/holidays/h1`).set({ name: 'x' })));


  // --- 구성원 관리 규칙 ---
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc('spaces/spaceY').set({ members: ['dad'], names: { dad: '아빠' } });
    await ctx.firestore().doc('spaces/spaceZ').set({ members: ['dad', 'mina'], banned: ['eve'], names: { dad: 'a', mina: 'b' } });
    await ctx.firestore().doc('spaces/spaceW').set({ members: ['dad'], banned: ['eve'] });
  });
  const eve = env.authenticatedContext('eve').firestore();
  const kim = env.authenticatedContext('kim').firestore();
  const { arrayUnion } = require('firebase/firestore');
  await t('멤버가 닉네임(names) 수정 허용', () => assertSucceeds(mina.doc('spaces/spaceZ').update({ 'names.mina': '민아' })));
  await t('멤버가 members에서 상대 빼기 차단', () => assertFails(dad.doc('spaces/spaceZ').update({ members: ['dad'] })));
  await t('멤버가 스스로 banned 바꾸기 차단', () => assertFails(dad.doc('spaces/spaceZ').update({ banned: [] })));
  await t('새 사람 참여(1명 공간) 허용', () => assertSucceeds(kim.doc('spaces/spaceY').update({ members: arrayUnion('kim'), 'names.kim': '킴' })));
  await t('세 번째 사람 참여 차단', () => assertFails(eve.doc('spaces/spaceZ').update({ members: arrayUnion('eve') })));
  await t('내보낸 사람(banned)이 다시 참여 차단', () => assertFails(eve.doc('spaces/spaceW').update({ members: arrayUnion('eve'), 'names.eve': 'e' })));
  await t('참여하면서 banned 비우기 차단', () => assertFails(eve.doc('spaces/spaceW').update({ members: arrayUnion('eve'), banned: [] })));

  for (const r of results) console.log(r.join('  '));
  const failed = results.filter(r => r[0] === 'FAIL').length;
  console.log(`\n${results.length - failed}/${results.length} 통과`);
  await env.cleanup();
  process.exit(failed ? 1 : 0);
})();
