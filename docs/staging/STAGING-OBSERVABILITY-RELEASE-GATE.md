# 🚨 ZORUNLU STAGING RELEASE KURALI — PAZARLIK YOK

# STAGING PAKET / STAGING BUILD VARSA **LOG GÖNDER** VE **CRASH TEST** BUTONLARI OLACAK.

Bu kural iOS ve Android için, local debug, staging release, CI/Firebase distribution ve staging endpoint'ine bağlanan TÜM paketler için geçerlidir. Uygulama sürümü, branch veya derleme yöntemi bu zorunluluğu kaldırmaz.

## Yayın engeli (RELEASE BLOCKER)

- Ayarlar'da **Log Gönder (UAT)** her staging build'de GÖRÜNÜR ve tıklanabilir olmalı; güvenli, sınırlandırılmış olaylar yetkilendirilmiş staging sunucusuna gönderilmeli.
- Backend **POST /v1/diagnostics/reports** aktif staging session ile **201 + reportId** dönmeli; reportId sunucu tarafında takip edilebilir olmalı. **404, 401, 403, 429 veya 5xx = test başarısız**; herhangi biri nedenine göre çözülmeden release onayı verilmez.
- Ayarlar'da **Crash Test (STAGING)** staging build'de GÖRÜNÜR olmalı. Firebase Crashlytics yapılandırılmamışsa bir neden gösterilmeli; başarı taklidi yapılmamalı. Yapılandırılmışsa onay diyaloğu sonrasında gerçek test crash tetiklenebilmeli ve staging Crashlytics projesinde görüldüğü doğrulanmalı.
- Yalnız **production** sürümlerde bu test kontrolleri gizli/kapalı olmalı. Production endpoint'inde diagnostic upload da sunucu tarafında engellenmeli.
- **PZD_STAGING_BASE_URL** tanımlı staging build, **PZD_DIAGNOSTIC_ENV** unutulsa bile diagnostic policy'yi etkinleştirmeli. Build-time yanlış ayar sessizce staging gözlemlenebilirliğini kapatmamalı.
- Credential, bearer token, Keychain secret, session secret, kişisel veri, ham request/response body ve ham URL hiçbir loga/Crashlytics'e gönderilmez.
- Bir staging dağıtımı kabul edilmeden iOS ve Android üzerinde buton görünürlüğü, gönderim sonucu ve sunucuda rapor doğrulanmalı; crash test ayrı onayla ve Firebase etkin olduğunda gerçekleştirilmelidir.

## UAT kabul kayıtları

1. Staging iOS build: Log Gönder görünür, POST 201 + reportId, sunucu eşleşmesi; Crash Test görünür ve Firebase durumunu doğru gösterir.
2. Staging Android build: aynı kontroller.
3. Production build: hiçbir test kontrolü gösterilmez, rapor endpoint'i deny.
4. Crashlytics configured staging build: bilinçli onayla tetiklenen test crash Crashlytics'te doğrulanır.
5. İlgili kontrollerden herhangi biri NOT_RUN/FAIL ise **GATE BLOCKED**.

**Bu belgenin amacı: staging gözlemlenebilirliğini bir kez daha unutulabilecek opsiyonel bir ayar olmaktan çıkarmaktır.**

Game mechanics / animations / tournament rules are out of scope.
