import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:logging_appenders/src/internal/dummy_logger.dart';
import 'package:logging_appenders/src/remote/base_remote_appender.dart';

final _logger = DummyLogger('logging_appenders.loki_appender');

/// Appender used to push logs to [Loki](https://github.com/grafana/loki).
class LokiApiAppender extends BaseDioLogSender {
  LokiApiAppender({
    required this.server,
    required this.labels,
  }); 

  final String server;
  final Map<String, String> labels;
  


  static final DateFormat _dateFormat =
      DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");

  Dio? _clientInstance;

  Dio get _client => _clientInstance ??= Dio();

  static String _encodeLineLabelValue(String value) {
    if (value.contains(' ')) {
      return json.encode(value);
    }
    return value;
  }

  @override
  Future<void> sendLogEventsWithDio(List<LogEntry> entries,
      Map<String, String> userProperties, CancelToken cancelToken) {
    final jsonObject =
        LokiPushBody([LokiStream(labels, entries)]).toJson();
    final jsonBody = jsonEncode(jsonObject, toEncodable: (dynamic obj) {
      if (obj is LogEntry) {

        obj.lineLabels.putIfAbsent('msg', () => obj.line);

        return [
          (obj.ts.microsecondsSinceEpoch*1000).toString(),         
            jsonEncode(obj.lineLabels),      
        ];
      }
      return obj;
    });
    return _client
        .post<dynamic>(
          server,
          cancelToken: cancelToken,
          data: jsonBody,
          options: Options(
            contentType: ContentType(
                    ContentType.json.primaryType, ContentType.json.subType)
                .value,
          ),
        )
        .then(
          (response) => Future<void>.value(null),
//      _logger.finest('sent logs.');
        )
        .catchError((Object err, StackTrace stackTrace) {
      String? message;
      if (err is DioError) {
        if (err.response != null) {
          message = 'response:${err.response!.data}';
          print(message);
        }
      }
      _logger.warning(
          'Error while sending logs to loki. $message', err, stackTrace);
      return Future<void>.error(err, stackTrace);
    });
  }
}

class LokiPushBody {
  LokiPushBody(this.streams);

  final List<LokiStream> streams;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'streams':
            streams.map((stream) => stream.toJson()).toList(growable: false),
      };
}

class LokiStream {
  LokiStream(this.labels, this.entries);

  final Map<String, String> labels;
  final List<LogEntry> entries;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'stream': labels, 'values': entries};
}
