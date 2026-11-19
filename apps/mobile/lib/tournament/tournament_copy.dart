import 'package:material_ui/material_ui.dart';

enum BadgeProvenanceLabel { f2bPublication, unavailable }

/// English and Turkish copy for the tournament UAT.
///
/// Material's built-in delegate in this app is English-only, so tournament
/// strings follow [TournamentLocale] rather than replacing that delegate.
final class TournamentLocale extends InheritedWidget {
  const TournamentLocale({
    super.key,
    required this.locale,
    required super.child,
  });

  final Locale locale;

  static Locale of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<TournamentLocale>();
    return inherited?.locale ?? const Locale('en');
  }

  @override
  bool updateShouldNotify(TournamentLocale oldWidget) =>
      oldWidget.locale != locale;
}

final class TournamentCopy {
  const TournamentCopy(this.locale);

  final Locale locale;

  bool get isTurkish => locale.languageCode == 'tr';

  String pick(String english, String turkish) => isTurkish ? turkish : english;

  static TournamentCopy of(BuildContext context) {
    return TournamentCopy(TournamentLocale.of(context));
  }

  String get appTitle => 'Puzzle Duel';
  String get tagline => pick(
    'Match shapes. Clear lines.',
    'Şekilleri eşleştir. Satırları temizle.',
  );
  String get dailyChallenge => pick('Daily challenge', 'Günlük mücadele');
  String get sixGames => pick('Six games', 'Altı oyun');
  String get playToday =>
      pick("Play today's tournament", 'Bugünün turnuvasını oyna');
  String get continueTournament =>
      pick('Continue tournament', 'Turnuvaya devam et');
  String get resume => pick('Resume tournament', 'Turnuvaya devam et');
  String get readyHeadline =>
      pick('Today’s tournament is open', 'Bugünün turnuvası açık');
  String get progressHeadline =>
      pick('Tournament in progress', 'Turnuva sürüyor');
  String get completedHeadline =>
      pick("Today's tournament completed", 'Bugünün turnuvası tamamlandı');
  String get weeklyRankings => pick('Weekly rankings', 'Haftalık sıralama');
  String get practiceLevels =>
      pick('Easy · Medium · Hard', 'Kolay · Orta · Zor');
  String get yourRank => pick('YOUR RANK', 'SENİN SIRAN');
  String get rankCaption => pick('Verified rank', 'Doğrulanmış sıra');
  String get settingsTitle => pick('Settings', 'Ayarlar');
  String get profile => pick('Profile', 'Profil');
  String get profileLater => pick(
    'Player profile arrives in a later update.',
    'Oyuncu profili sonraki güncellemede gelecek.',
  );
  String get playerFallback => pick('Player', 'Oyuncu');
  String get personalRecordsTitle =>
      pick('Practice records', 'Pratik rekorları');
  String get noPersonalBest => pick('No record yet.', 'Henüz rekorun yok.');
  String get unverifiedLocal => pick('Local only', 'Yalnızca yerel');
  String get badgeCollectionTitle =>
      pick('Badge collection', 'Rozet koleksiyonu');
  String get badgeCollectionBlurb => pick(
    'Verified tournament achievements only. Practice cannot unlock these.',
    'Yalnızca doğrulanmış turnuva başarıları. Pratik bunları açmaz.',
  );
  String get badgeLoading => pick('Loading badges…', 'Rozetler yükleniyor…');
  String get badgeEmpty => pick(
    'No verified badges yet. Finish a daily tournament on time to earn On-Time.',
    'Henüz doğrulanmış rozet yok. Zamanında rozeti için günlük turnuvayı zamanında bitir.',
  );
  String get badgeOffline => pick(
    'Offline. Practice records stay available; badges update when you reconnect.',
    'Çevrimdışı. Pratik kayıtların duruyor; rozetler bağlantı gelince güncellenir.',
  );
  String get badgeAuthRequired => pick(
    'Sign in again to load verified badges.',
    'Doğrulanmış rozetler için yeniden oturum aç.',
  );
  String get badgeServerError =>
      pick('Badges could not be loaded.', 'Rozetler yüklenemedi.');
  String get badgeLocked => pick('Locked', 'Kilitli');
  String get onTimeBadgeDescription => pick(
    'Awarded when the daily tournament claim starts inside the UTC day window.',
    'Günlük turnuva kaydı UTC gün penceresinde başladığında verilir.',
  );
  String get onTimeBadgeRule => pick(
    'Server-authoritative. Device clock and practice scores never grant this badge.',
    'Sunucu otoritesindedir. Cihaz saati ve pratik skorları bu rozeti vermez.',
  );
  String get profileNoActivity => pick(
    'No completed practice games on this device yet.',
    'Bu cihazda henüz tamamlanmış pratik oyunu yok.',
  );
  String profileActivitySummary(int completed) => pick(
    '$completed completed practice game${completed == 1 ? '' : 's'} on this device.',
    'Bu cihazda $completed tamamlanmış pratik oyunu.',
  );
  String badgeEarnedCount(int count) => pick(
    count == 1 ? 'Earned once' : 'Earned $count times',
    count == 1 ? '1 kez kazanıldı' : '$count kez kazanıldı',
  );
  String badgeLastEarned(String day) =>
      pick('Last earned $day', 'Son kazanım $day');
  String badgeProvenanceLabel(BadgeProvenanceLabel provenance) =>
      switch (provenance) {
        BadgeProvenanceLabel.f2bPublication => pick(
          'Source: verified tournament publication',
          'Kaynak: doğrulanmış turnuva yayını',
        ),
        BadgeProvenanceLabel.unavailable => pick(
          'Source: not verified on this device',
          'Kaynak: bu cihazda doğrulanmadı',
        ),
      };
  String recordMeta({
    required String completedAt,
    required String rulesVersion,
    int? moveCount,
  }) {
    final date = completedAt.length >= 10
        ? completedAt.substring(0, 10)
        : completedAt;
    final moves = moveCount == null
        ? ''
        : pick(' · $moveCount moves', ' · $moveCount hamle');
    return pick('$date · $rulesVersion$moves', '$date · $rulesVersion$moves');
  }

  String get soundBody => pick(
    'Sounds for placements, clears, and results.',
    'Yerleştirme, temizleme ve sonuç sesleri.',
  );
  String get hapticsBody => pick(
    'Vibration for selections and results.',
    'Seçim ve sonuç titreşimi.',
  );
  String get showMore =>
      pick('Show more verified scores', 'Daha fazla doğrulanmış puan');
  String get serverRanks => pick(
    'Ranks and scores come from the server.',
    'Sıra ve puan sunucudan gelir.',
  );
  String get oneVerified => pick(
    'One verified score on this board.',
    'Bu tabloda bir doğrulanmış puan var.',
  );
  String get personalBest =>
      pick('Personal best on this device', 'Bu cihazdaki en iyi sonuç');
  String get bestOnDevice => pick('Best on this device', 'Bu cihazdaki en iyi');
  String get stageComplete => pick('Stage complete', 'Aşama tamam');
  String get previousWeek => pick('Previous week', 'Önceki hafta');
  String get newerWeek => pick('Later week', 'Sonraki hafta');
  String get continueNext => pick('Continue', 'Devam');
  String get viewResults => pick('View results', 'Sonuçları gör');
  String get returnHome => pick('Return Home', 'Ana sayfaya dön');
  String get homeAction => pick('Home', 'Ana sayfa');
  String get viewLeaderboard => pick('View Leaderboard', 'Sıralamayı gör');
  String get seeGames => pick("Today's games", 'Bugünün oyunları');
  String get dailyBoard => pick('Daily leaderboard', 'Günlük sıralama');
  String get weeklyBoard => pick('Weekly leaderboard', 'Haftalık sıralama');
  String get readyBody => pick(
    'One daily entry. Six games. The server scores every move.',
    'Günde bir giriş. Altı oyun. Her hamleyi sunucu puanlar.',
  );
  String get alreadyClaimed => pick(
    'Today is already claimed. This is the same series.',
    'Bugün zaten alındı. Aynı seri devam ediyor.',
  );
  String get completedBody =>
      pick('Today’s tournament is complete.', 'Bugünün turnuvası tamam.');
  String get verifiedScore => pick('Verified score', 'Doğrulanmış puan');
  String get currentScore => pick('Current score', 'Güncel puan');
  String get scoreUnavailable =>
      pick('Score not published yet', 'Puan henüz yayımlanmadı');
  String get onTime => pick('On-Time', 'Zamanında');
  String get onTimeMissing =>
      pick('On-Time not awarded', 'Zamanında rozeti yok');
  String get overviewTitle => pick("Today's six games", 'Bugünün altı oyunu');
  String get overviewBody => pick(
    'E1, E2 and E3 are Easy. M1 and M2 are Medium. H1 is Hard. Each board comes from the server.',
    'E1, E2 ve E3 Kolay. M1 ve M2 Orta. H1 Zor. Her tahta sunucudan gelir.',
  );
  String get back => pick('Back', 'Geri');
  String get leaveTitle => pick('Leave this game?', 'Bu oyundan çıkılsın mı?');
  String get leaveBody => pick(
    'Today’s series stays on the server. You can resume it from Home. Leaving does not add time.',
    'Bugünün serisi sunucuda durur. Ana sayfadan devam edebilirsin. Çıkmak süre eklemez.',
  );
  String get stay => pick('Keep playing', 'Oynamaya devam');
  String get leave => pick('Go to Home', 'Ana sayfaya git');
  String get selectPiece => pick('Selected', 'Seçili');
  String get sending => pick('Sending this move…', 'Bu hamle gönderiliyor…');
  String get unknownCommand => pick(
    'The outcome is unknown. Retry only this move.',
    'Sonuç bilinmiyor. Yalnızca bu hamleyi yeniden dene.',
  );
  String get retrySame =>
      pick('Retry the same move', 'Aynı hamleyi yeniden dene');
  String get idle => pick('Time to move', 'Hamle süresi');
  String get leaderboard => pick('Leaderboard', 'Sıralama');
  String get practice => pick('Practice', 'Pratik Yap');
  String get practiceTitle => pick('Practice', 'Pratik Yap');
  String get practiceBlurb => pick(
    'Unlimited puzzles. Not ranked and not part of today’s tournament.',
    'Sınırsız bulmaca. Sıralamaya girmez ve bugünün turnuvasına yazılmaz.',
  );
  String get chooseDifficulty => pick('Choose a difficulty', 'Zorluk seç');
  String get newPuzzle => pick('New Puzzle', 'Yeni bulmaca');
  String get samePuzzle =>
      pick('Replay Same Puzzle', 'Aynı bulmacayı tekrarla');
  String get changeDifficulty => pick('Change Difficulty', 'Zorluğu değiştir');
  String get practiceDone => pick('Practice complete', 'Pratik tamamlandı');
  String get practiceLocal => pick(
    'Saved on this device only. This is not a verified rank.',
    'Yalnızca bu cihazda durur. Doğrulanmış bir sıralama değildir.',
  );
  String get unranked => pick(
    'You have no verified rank on this board.',
    'Bu tabloda doğrulanmış sıran yok.',
  );
  String get weeklyTab => pick('Weekly', 'Haftalık');
  String get dailyTab => pick('Daily', 'Günlük');
  String get soundSetting => pick('Sound', 'Ses');
  String get hapticsSetting => pick('Haptics', 'Titreşim');
  String get verifiedPlayer => pick('Player', 'Oyuncu');
  String budgetLine(int size, int moves) => pick(
    '$size×$size board, $moves moves',
    '$size×$size tahta, $moves hamle',
  );
  String get gameScore => pick('Game score', 'Oyun puanı');
  String get totalScore => pick('Total', 'Toplam');
  String get nextGame => pick('Next', 'Sonraki');
  String get finishedTitle => pick('Game complete', 'Oyun bitti');
  String get moveLimitEnded => pick(
    'The move limit ended this game.',
    'Hamle hakkı bitince oyun kapandı.',
  );
  String get noMovesEnded => pick(
    'No legal placement remains.',
    'Yerleştirilecek yasal hamle kalmadı.',
  );
  String get gameFinished =>
      pick('This game was closed remotely.', 'Bu oyun uzaktan kapatıldı.');
  String get resultsTitle => pick('Tournament complete', 'Turnuva tamam');
  String get resultsPending => pick(
    'The verified result is not available yet.',
    'Doğrulanmış sonuç henüz yok.',
  );
  String get easy => pick('Easy', 'Kolay');
  String get medium => pick('Medium', 'Orta');
  String get hard => pick('Hard', 'Zor');
  String get all => pick('All', 'Tümü');
  String get you => pick('You', 'Sen');
  String get emptyBoard => pick(
    'No verified scores on this board yet.',
    'Bu tabloda henüz doğrulanmış puan yok.',
  );
  String get notOnPage =>
      pick('Your rank is not on this page.', 'Sıralaman bu sayfada değil.');
  String get provisional => pick('Provisional', 'Geçici');
  String get finalLabel => pick('Final', 'Kesinleşti');
  String get tryAgain => pick('Try again', 'Yeniden dene');
  String get loading => pick('Loading the tournament…', 'Turnuva yükleniyor…');
  String get tournamentSyncing => pick(
    'Updating tournament info…',
    'Turnuva bilgileri güncelleniyor…',
  );
  String get tournamentRefreshSuccess => pick(
    'Tournament info updated.',
    'Turnuva bilgileri güncellendi.',
  );
  String get cachedTournamentHeadline => pick(
    'Your latest tournament info',
    'Son turnuva bilgilerin',
  );
  String get cachedTournamentBody => pick(
    'Showing your latest tournament info.',
    'Son turnuva bilgilerin gösteriliyor.',
  );
  String get connectionUnavailable => pick(
    'No internet connection.',
    'İnternet bağlantısı yok.',
  );
  String get noConnection => pick('No connection', 'Bağlantı yok');
  String get boardLoading =>
      pick('Loading verified scores…', 'Doğrulanmış puanlar yükleniyor…');
  String get reference => pick('Reference', 'Referans');
  String get unauthorized => pick(
    'Sign in again to update tournament info.',
    'Turnuva bilgilerini güncellemek için yeniden oturum aç.',
  );
  String get timedOut => pick(
    'Connection timed out.',
    'Bağlantı zaman aşımına uğradı.',
  );
  String get offline => pick(
    'No internet connection.',
    'İnternet bağlantısı yok.',
  );
  String get writerBlocked => pick(
    'Today’s ranked challenge is locked to another session on this account. Practice stays available.',
    'Bugünün sıralı mücadelesi bu hesapta başka bir oturuma kilitli. Pratik kullanılabilir.',
  );
  String get staleBoard => pick(
    'The board changed. Showing the latest position.',
    'Tahta değişti. Güncel konum gösteriliyor.',
  );
  String get couldNotRead => pick(
    'That request could not be read. Try again.',
    'İstek okunamadı. Yeniden dene.',
  );
  String get rateLimited => pick(
    'Too many requests. Wait and retry the same move.',
    'Çok fazla istek. Bekle ve aynı hamleyi dene.',
  );
  String get windowClosed => pick(
    'Today’s claim window is closed.',
    'Bugünün kayıt penceresi kapalı.',
  );
  String get rejectedMove => pick(
    'That move was not accepted. Try again.',
    'Hamle kabul edilmedi. Yeniden dene.',
  );
  String get genericFailure =>
      pick('Something went wrong.', 'Bir şeyler ters gitti.');
  String get boardUnreadable => pick(
    'The board could not be shown.',
    'Tahta gösterilemedi.',
  );

  String objective(int moves, int size) => pick(
    'Select a piece, then tap a highlighted empty tile. $moves moves left on a $size×$size board.',
    'Bir parça seç, sonra vurgulanan boş kareye dokun. $size×$size tahtada $moves hamle kaldı.',
  );

  String movesLeft(int moves) => pick('$moves left', '$moves kaldı');

  String rankLabel(Object? rank) => pick('Rank $rank', 'Sıra $rank');

  String difficultyOf(String? label) {
    if (label == null || label.isEmpty) return '';
    if (label.startsWith('E')) return easy;
    if (label.startsWith('M')) return medium;
    if (label.startsWith('H')) return hard;
    return label;
  }

  String finishReason(String? reason) {
    return switch (reason) {
      'move_limit_reached' => moveLimitEnded,
      'no_legal_moves' => noMovesEnded,
      _ => gameFinished,
    };
  }

  String forError(String? code) {
    return switch (code) {
      'TIMEOUT' => timedOut,
      'OFFLINE' => offline,
      'UNAUTHENTICATED' => unauthorized,
      'WRITER_NOT_AUTHORIZED' => writerBlocked,
      'STATE_CONFLICT' => staleBoard,
      'MALFORMED_REQUEST' => couldNotRead,
      'RATE_LIMITED' => rateLimited,
      'CLAIM_WINDOW_CLOSED' => windowClosed,
      'outcome_unknown' => unknownCommand,
      'BOARD_UNREADABLE' => boardUnreadable,
      null || '' => genericFailure,
      _ => rejectedMove,
    };
  }

  String categoryLabel(String category) {
    return switch (category) {
      'EASY' => easy,
      'MEDIUM' => medium,
      'HARD' => hard,
      'ALL' => all,
      _ => category,
    };
  }

  String groupedScore(int value) {
    final raw = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var index = 0; index < raw.length; index++) {
      if (index > 0 && (raw.length - index) % 3 == 0) {
        buffer.write(isTurkish ? '.' : ',');
      }
      buffer.write(raw[index]);
    }
    return buffer.toString();
  }

  String weekRange(String start) => _formatRange(start, isTurkish);

  String dayLabel(String day) => _formatDay(day, isTurkish);
}

const _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _turkishMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

DateTime? _utcDay(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

String _monthName(int month, bool turkish) {
  return (turkish ? _turkishMonths : _englishMonths)[month - 1];
}

String _formatDay(String value, bool turkish) {
  final day = _utcDay(value);
  if (day == null) return value;
  return '${day.day} ${_monthName(day.month, turkish)} ${day.year}';
}

String _formatRange(String start, bool turkish) {
  final first = _utcDay(start);
  if (first == null) return start;
  final last = first.add(const Duration(days: 6));
  if (first.month == last.month && first.year == last.year) {
    return '${first.day}–${last.day} ${_monthName(first.month, turkish)} ${first.year}';
  }
  if (first.year == last.year) {
    return '${first.day} ${_monthName(first.month, turkish)}–${last.day} ${_monthName(last.month, turkish)} ${first.year}';
  }
  return '${_formatDay(start, turkish)}–${last.day} ${_monthName(last.month, turkish)} ${last.year}';
}

final class TournamentCopyDelegate
    extends LocalizationsDelegate<TournamentCopy> {
  const TournamentCopyDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<TournamentCopy> load(Locale locale) async => TournamentCopy(locale);

  @override
  bool shouldReload(covariant TournamentCopyDelegate old) => false;
}
