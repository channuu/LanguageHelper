class LastImportSummary {
  final DateTime importedAt;
  final int newWords;
  final int newSentences;
  final int skippedWords;
  final int skippedSentences;

  const LastImportSummary({
    required this.importedAt,
    required this.newWords,
    required this.newSentences,
    required this.skippedWords,
    required this.skippedSentences,
  });

  Map<String, Object?> toJson() => {
        'importedAt': importedAt.toIso8601String(),
        'newWords': newWords,
        'newSentences': newSentences,
        'skippedWords': skippedWords,
        'skippedSentences': skippedSentences,
      };

  factory LastImportSummary.fromJson(Map<String, Object?> json) => LastImportSummary(
        importedAt: DateTime.parse(json['importedAt'] as String),
        newWords: json['newWords'] as int,
        newSentences: json['newSentences'] as int,
        skippedWords: json['skippedWords'] as int,
        skippedSentences: json['skippedSentences'] as int,
      );
}
