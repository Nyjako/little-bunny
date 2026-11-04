const _videoExtensions = {'webm', 'mp4'};

/// True for a post's video file extensions -- `PostDetailScreen` plays these
/// in place with `video_player`, `PostGridTile` (M9.7.3) marks them with a
/// play-icon overlay before they're even opened.
bool isVideoExt(String? ext) => ext != null && _videoExtensions.contains(ext.toLowerCase());

/// True for an animated GIF -- still rendered as a plain (animated) image via
/// `CachedNetworkImage`, not the video player, but still worth marking on a
/// grid thumbnail (M9.7.3) the same way a video is.
bool isGifExt(String? ext) => ext != null && ext.toLowerCase() == 'gif';

const _audioExtensions = {'mp3'};

/// True for an Inkbunny Music submission's file extension (M28 Phase 4) --
/// the only one actually observed live is mp3. `PostDetailScreen` plays
/// these with `AudioPlayerWidget` instead of the image/video dispatch.
bool isAudioExt(String? ext) => ext != null && _audioExtensions.contains(ext.toLowerCase());

const _textDocumentExtensions = {'txt', 'md'};

/// True for a plain-text Inkbunny "Writing - Document" submission (M28
/// submission-type coverage follow-up) -- `PostDetailScreen` fetches and
/// renders these inline via `TextDocumentViewer` rather than the generic
/// "this file format isn't supported yet" fallback every other unknown
/// extension gets. Deliberately narrow (not .pdf/.doc/.docx/.rtf, which
/// aren't plain UTF-8 text and would need a real document renderer, not
/// just a decode-and-display) -- those still fall back to the generic
/// message, now with an "open externally" link alongside it.
bool isTextDocumentExt(String? ext) => ext != null && _textDocumentExtensions.contains(ext.toLowerCase());
