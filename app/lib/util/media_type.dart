const _videoExtensions = {'webm', 'mp4'};

/// True for a post's video file extensions -- `PostDetailScreen` plays these
/// in place with `video_player`, `PostGridTile` (M9.7.3) marks them with a
/// play-icon overlay before they're even opened.
bool isVideoExt(String? ext) => ext != null && _videoExtensions.contains(ext.toLowerCase());

/// True for an animated GIF -- still rendered as a plain (animated) image via
/// `CachedNetworkImage`, not the video player, but still worth marking on a
/// grid thumbnail (M9.7.3) the same way a video is.
bool isGifExt(String? ext) => ext != null && ext.toLowerCase() == 'gif';
