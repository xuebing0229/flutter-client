class UpdateManifest {
  const UpdateManifest({
    required this.schema,
    required this.channel,
    required this.version,
    required this.build,
    required this.published,
    required this.downloadUri,
    required this.notes,
    this.sizeBytes,
    this.sha256,
  });

  final int schema;
  final String channel;
  final String version;
  final int build;
  final bool published;
  final Uri? downloadUri;
  final String notes;
  final int? sizeBytes;
  final String? sha256;

  bool isNewerThan(int currentBuild) => published && build > currentBuild;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final schema = json['schema'];
    final channel = json['channel'];
    final version = json['version'];
    final build = json['build'];
    final published = json['published'];
    final download = json['download_url'];
    final notes = json['notes'];
    final sizeBytes = json['size_bytes'];
    final sha256 = json['sha256'];

    if (schema is! int || schema != 1) {
      throw const FormatException('更新信息版本无效。');
    }
    if (channel is! String || channel.isEmpty) {
      throw const FormatException('更新渠道格式无效。');
    }
    if (version is! String || version.isEmpty) {
      throw const FormatException('更新版本号格式无效。');
    }
    if (build is! int || build < 0) {
      throw const FormatException('更新构建号格式无效。');
    }
    if (published is! bool) {
      throw const FormatException('更新发布状态格式无效。');
    }
    if (download != null && (download is! String || download.isEmpty)) {
      throw const FormatException('更新下载地址格式无效。');
    }
    if (notes is! String) {
      throw const FormatException('更新说明格式无效。');
    }
    if (sizeBytes != null && (sizeBytes is! int || sizeBytes <= 0)) {
      throw const FormatException('更新文件大小格式无效。');
    }
    if (sha256 != null &&
        (sha256 is! String ||
            !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256))) {
      throw const FormatException('更新文件校验值格式无效。');
    }

    return UpdateManifest(
      schema: schema,
      channel: channel,
      version: version,
      build: build,
      published: published,
      downloadUri: download == null ? null : Uri.parse(download as String),
      notes: notes,
      sizeBytes: sizeBytes as int?,
      sha256: (sha256 as String?)?.toLowerCase(),
    );
  }
}
