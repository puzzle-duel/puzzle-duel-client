# 🚨 ZORUNLU STAGING RELEASE KURALI — PAZARLIK YOK

# STAGING PAKET / STAGING BUILD VARSA **LOG GÖNDER** VE **CRASH TEST** BUTONLARI OLACAK.

**ZORUNLU OKUMA:** Her geliştirme task'ına başlamadan önce bu dosya okunacak; yeni ekran/request/hata akışının tipli log sözleşmesi burada tanımlıdır. Agent yönlendirmeleri: repository kökündeki `AGENTS.md`.

Bu kural iOS ve Android için, local debug, staging release, CI/Firebase distribution ve staging endpoint'ine bağlanan TÜM paketler için geçerlidir. Uygulama sürümü, branch veya derleme yöntemi bu zorunluluğu kaldırmaz.

## Yayın engeli (RELEASE BLOCKER)

**ABSOLUTE NO-REGRESSION — Log Gönder (UAT):** No action or change may negatively impact manual diagnostic upload, its visibility, authorized guest/verified-account operation, HTTP 201 + reportId delivery, or Request ID / Report ID Inspector correlation. Before every change assess impact; after every development run applicable regression tests and verify end-to-end on staging before merge/release/Done. FAIL or NOT_RUN blocks acceptance; green CI alone is insufficient. Never bypass authentication, redaction, or production isolation; never fake success. If a regression is found, prioritize restoring diagnostics before unrelated work.

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

---

## ZORUNLU GELİŞTİRME SÖZLEŞMESİ — her task başlamadan oku

**Kapsam:** Flutter iOS + Android, Firebase Crashlytics custom logs, HTTP request aksiyonları, backend staging HTTP diagnostics, UAT rapor sorgulaması. Yeni bir ekran, navigasyon olayı, request, auth/session işlemi veya hata senaryosu ekleyen/değiştiren HER PR için geçerlidir. Yalnızca release kontrolü değildir.

**İlk adım:** `AGENTS.md` → **bu belge** → `docs/staging/SERVER-CONFIG.md` → `apps/mobile/firebase/STAGING_BUILD.md` → ilgili özelliğin sözleşmesi. PR'da logging etkisi ve doğrulama sonucu açıkça yazılmadan Done/merge/deploy onayı verilmez. Gameplay, animasyon veya turnuva kuralı bu çalışma kapsamında değiştirilmez.

### 1. Mevcut kaynak kodu ve tek logging hattı

| Sorumluluk | Kaynak |
| --- | --- |
| Tipli, gizlilik güvenli olay şeması (`LogCode`, `LogEvent`) | `apps/mobile/lib/diagnostics/puzzle_duel_logger.dart` |
| Console + Crashlytics + bellek ring buffer | `apps/mobile/lib/diagnostics/diagnostic_runtime.dart` |
| Firebase SDK başlatma, Crashlytics sink, test nonfatal/crash | `apps/mobile/lib/diagnostics/firebase_crashlytics_adapter.dart` |
| Ekran navigasyon breadcrumb'ları | `apps/mobile/lib/diagnostics/screen_breadcrumb_observer.dart` |
| Staging/production diagnostic policy | `apps/mobile/lib/diagnostics/diagnostic_policy.dart` |
| HTTPS request ID, HTTP başlangıç/başarı/hata ve manuel rapor | `apps/mobile/lib/tournament/uat_api.dart` |
| Backend HTTP correlation / güvenli route sınıflaması | `puzzle-duel-backend/src/diagnostics/http-correlation.mts` |
| Backend request log dosyası / session olayları | `puzzle-duel-backend/src/staging/staging-server.mts` |
| Personal records (PZD-53) GET/sync + Crashlytics operations | `fetchPersonalRecords`, `syncPracticeRecords`; route `profile_personal_records` |

**Bütün uygulama katmanları `DiagnosticRuntime.logger.log(LogEvent(...))` üzerinden ilerler.** Bağımsız, serbest metin içeren başka Firebase logger'ı veya request log sistemi oluşturma. `CrashlyticsLogSink` olayları Firebase custom log'a yönlendirir ve mevcut `last_request_id` custom key'ini günceller. Firebase'e doğrudan ham veri yazma. `ConsoleLogSink` ve `RingBufferLogSink` davranışını koru. Firebase devre dışıysa no-op; varmış gibi başarı raporlama.

### 2. Her ekran ve kullanıcı aksiyonu için breadcrumb

- Ekran açılışı/navigation: mevcut `ScreenBreadcrumbObserver` üzerinden `LogCode.screenOpened`. Route adının sabit, güvenli ve 64 karakteri aşmayan bir operation olması gerekir. Observer olmayan açılışlar için aynı tipli logger ile açık bir event eklenir.
- Önemli UI / view lifecycle / buton / fetch aksiyonu: eylem başladığında `LogEvent(level: LogLevel.info, code: ..., operation: ...)` kaydı. **Mevcut enum kodlarından semantik olarak uygun olanı kullan.** Yeni eylem tipi için `LogCode` gerekiyorsa hem istemci rapor şeması hem backend allowlist/inspector eşzamanlı güncellenmeden gönderilmiş rapora yeni kod koyma.
- Beklenen log okunabilirliği: `PZDProfile:: viewDidLoad called`, `PZDProfile:: fetchAllBadges called`, `PZDProfile:: fetchAllBadges success` / `failed` mantığında, fakat **Swift/UIKit isimlerini Flutter'a birebir taşımaya çalışma**: mevcut Crashlytics sink biçimi `operation:: phase` üretir. Gerçek route/widget ve operation adını kullan.
- Başarı ve hata ayrı görünmeli; ekranı açan request'in hangi aksiyon tarafından tetiklendiği anlaşılmalı. Gerekirse aynı isteğe `traceId` bağla. Navigasyon kaydı tek başına API aksiyonunu belgelemek için yeterli değildir.
- Her fail yolunda allowlist'e uygun `errorCode`; HTTP ise status/duration; oturum/yazar reddi ise mevcut `auth*` / `session*` / `writerBindingRejected` olaylarıyla doğru kategoriyi kullan.

**Önemli mevcut kısıt:** `LogCode` şu anda `applicationStarted`, `screenOpened`, `httpStarted`, `httpCompleted`, `httpFailed`, `authExpired`, `authRefreshSucceeded`, `authRefreshFailed`, `sessionRestored`, `sessionRestoreFailed`, `writerBindingRejected`, `diagnosticFailure` değerlerini içerir. Serbest yeni kod, `operation` veya exception metni üretme. **Mevcut rapor endpoint'i `screenOpened` ve `httpStarted` olaylarını kabul edilen manuel rapordan filtreler;** bu olaylar console/ring buffer/Crashlytics breadcrumb olarak kalır. Gerekiyorsa genişletme için açık bir istemci + backend contract task aç ve test et; sessizce rapora ekleme.

### 3. Her HTTP request aksiyonu için zorunlu olay zinciri

1. İstek başlamadan benzersiz 128-bit / **32 lowercase hex** `requestId` oluştur; `LogCode.httpStarted` bas.
2. Aynı değeri HTTPS isteğinin `x-request-id` header'ında backend'e gönder. İlgili user action'ı birden fazla isteği kapsıyorsa güvenli `traceId` ile ilişkilendir.
3. Başarılı response: aynı `requestId` ile `LogCode.httpCompleted`, `httpVerb`, `httpStatus`, `durationMs`, sabit `operation` kaydet.
4. HTTP 4xx/5xx, timeout, transport, parse ve auth/session reddi: uygun `LogCode.httpFailed` / protokol olayı ve **sanitize edilmiş** `errorCode`; gerçek başarısızlığı loglamak zorunlu, 2xx gibi gösterme.
5. Backend request lifecycle kaydı aynı `requestId`, route kategorisi, method, HTTP status, duration ve allowlist hata koduyla `http-diagnostics.log` üzerinde oluşur. **Log yazımı request davranışını bloke etmez.**
6. Request'ler `UatApi` dışında yeni bir HTTP istemcisinden geçecekse, aynı correlation sözleşmesini uygula, parity testi ekle; token/URL/body loglama.

Örnek tipli olay (mevcut API'ye uygun, gerçek status/ID çağrıdan alınmalı):

```dart
unawaited(DiagnosticRuntime.logger.log(LogEvent(
  level: LogLevel.info,
  code: LogCode.httpCompleted,
  operation: 'fetchAllBadges',
  requestId: requestId,
  httpVerb: HttpVerb.get,
  httpStatus: response.statusCode,
  durationMs: stopwatch.elapsedMilliseconds,
)));
```

**İki ayrı sistem:** Firebase custom logs **crash öncesi breadcrumb** içindir; Oracle **HTTP request kanıtı ve manuel diagnostic report** içindir. Firebase Crashlytics loglarını Oracle Inspector'ın otomatik olarak okuduğunu veya `Log Gönder` butonunun Firebase'e rapor yüklediğini iddia etme.

### 4. Staging Report ID / Request ID ile log inceleme

Workflow: [PZD Staging Unified Request Log Inspector](https://github.com/puzzle-duel/puzzle-duel-backend/actions/workflows/staging-diagnostic-status.yml)

- `request_id`: 32 lowercase hex. Tek isteğin backend HTTP kayıtlarını ve saklanan, ilişkili client diagnostic olaylarını arar.
- `report_id`: uygulamanın `Log Gönder (UAT)` akışında, backend'in **POST /v1/diagnostics/reports → HTTP 201 + reportId** yanıtıyla üretilmiş lowercase UUID. UUID'yi request ID sanma.
- **Yalnızca bir alanı doldur.** Her ikisi boşsa aktif + rotate edilmiş HTTP loglarından **son 1 MiB** okunur. Yanlış alana doğru formatlı ID girilmişse Inspector türünü düzeltebilir; bu özelliği yanlış format kullanmak için bahane etme.
- Workflow çıktısı yalnızca güvenli operasyonel metadata içerir: HTTP status, method, route kategorisi, süre, allowlist hata ve istemci event kategorisi. **Tam ham log/PII/token dökümü değildir**.
- Saklama sınırlı: istemci ring buffer şu anda **300 event / 256 KiB / 2 saat**, manuel rapor **en fazla 64 event**, backend raporların ömrü sınırlı, HTTP log rotasyonu var. "Not retained" = veri o anda bulunamadı; **servis sağlıklı veya hata yok** anlamına gelmez.
- Rapor akışı auth/session gerektirir; `400/401/403/404/429/5xx` başarısızdır. `429` yeniden deneme sınırı; tüm id'leri/ham payload'ı loglama.
- İnceleme sonuçlarında `requestId` / `reportId` korelasyonu doğrulanmadıkça, kullanıcıya "sunucuda görüldü" veya "sorunsuz" deme.

### 5. Firebase Crashlytics custom logging ve release kanıtı

- Project: **`puzzle-duel-staging`**. Staging native config opt-in. `PZD_STAGING_FIREBASE=1` (iOS), Android'de `ORG_GRADLE_PROJECT_pzdStagingFirebase=true`, `PZD_FIREBASE_CONFIGURED=true`, `PZD_DIAGNOSTIC_ENV=staging`, `PZD_STAGING_DIAGNOSTICS=true` parametrelerini ilgili build yönergesine göre kullan.
- Firebase SDK hazır değilken log sink no-op olabilir. İlgili CI/build geçmesi **Crashlytics ingest edildi** demek değildir; Dashboard'da olayın, gerekiyorsa dSYM/stack symbolication'ın görüldüğünü ayrı doğrula.
- Kullanıcı onaylı staging crash testi dışında gerçek crash tetikleme. Diagnostic log'a ham crash exception.toString(), stack, token, user ID, e-posta, request/response body gönderme.
- **Her ekrandan en az bir açılış breadcrumb'ı ve her kritik request'ten start + success/fail fazları Crashlytics custom logs'ta görünür olmalı**; ilgili test üretmeden/çalıştırmadan görev Done olamaz.
- Manual `Log Gönder` butonu, `Crash Test`, testler ve staging/production gating için belgenin üstündeki **RELEASE BLOCKER** aynen geçerlidir.

### 6. PR checklist ve görev kapanış kapısı

- [ ] Bu belge ve `AGENTS.md` görev başlangıcında okundu; mevcut source/contract incelendi.
- [ ] Yeni/değişen ekran, önemli user action ve tüm HTTP start/success/failure yolları için **tipli, sabit operation** tanımlandı.
- [ ] Request ID header ve event'te aynı; session/trace correlation korunuyor.
- [ ] Firebase custom logs'ta gerçek ekran/aksiyon breadcrumb'ları gösterildi; no-op durumu saklanmadı.
- [ ] Report ID ile 201 → Inspector ve Request ID → Inspector uçtan uca test edildi veya **NOT_RUN/BLOCKED** olarak açıkça yazıldı.
- [ ] Redaction: token, kimlik, URL, body, session secret, credentials, stack ve rastgele exception hiçbir sink'e sızmıyor.
- [ ] iOS/Android staging test kontrolleri ve production izolasyonu gerilemedi.
- [ ] `flutter analyze`, `flutter test`, ilgili backend typecheck / staging testleri ve gerçek cihaz UAT sonucu kaydedildi; yapılmayan teste PASS denmedi.
- [ ] Gameplay, grafik, animasyon, turnuva ve hesap bağlama kapsam dışındaysa **değiştirilmedi**.

**Gökhan/Serap named-player provisioning/enrollment:** kaldırılmıştır; bu belgeden herhangi bir task'a geri ekleme izni çıkmaz. Var olan legacy / Player A / Player B staging guest sistemi ayrı bir sözleşmedir; logging amacıyla yeni kimlik akışı üretme.
