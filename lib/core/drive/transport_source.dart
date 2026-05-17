// lib/core/drive/transport_source.dart
//
// Which transport the user picked on the Get Maps screen (Issue #45).
// Google Drive is the original FireCheck path. FTP/FileZilla is the
// alternate path GIS specialists asked for so the team can hand off data
// over network environments where Drive isn't reliable.
enum TransportSource { googleDrive, ftp }
