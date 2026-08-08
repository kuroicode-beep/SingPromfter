import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/services/ollama_client.dart';

void main() {
  group('buildPolishBody — 스타일 다듬기 요청', () {
    test('모델·비스트리밍·시스템 프롬프트가 실린다', () {
      final body = buildPolishBody(
        model: 'gemma4:12b',
        koreanPrompt: '잔잔한 발라드, 피아노와 현악',
      );
      expect(body['model'], 'gemma4:12b');
      expect(body['stream'], isFalse);
      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
      expect((messages[0] as Map)['role'], 'system');
      expect((messages[0] as Map)['content'], contains('영어 스타일 태그'));
      expect((messages[1] as Map)['content'], contains('잔잔한 발라드'));
    });
  });

  group('buildLyricsTagBody — 가사 구조 태깅', () {
    test('내용·언어를 바꾸지 말라는 지시가 들어간다', () {
      final body = buildLyricsTagBody(model: 'm', lyrics: '별빛이 내리는 밤');
      final system = ((body['messages'] as List)[0] as Map)['content'] as String;
      expect(system, contains('바꾸지 말'));
      expect(system, contains('[verse]'));
    });
  });

  group('parseChatContent — /api/chat 응답', () {
    test('message.content를 다듬어 돌려준다', () {
      expect(
        parseChatContent({
          'message': {'content': '  calm ballad, piano  '},
        }),
        'calm ballad, piano',
      );
    });

    test('빈 응답·형식 오류는 null', () {
      expect(parseChatContent({'message': {'content': '   '}}), isNull);
      expect(parseChatContent({'message': 'oops'}), isNull);
      expect(parseChatContent('not a map'), isNull);
      expect(parseChatContent(null), isNull);
    });
  });

  group('OllamaClient.hasModel — 모델 존재 판정', () {
    const models = ['gemma4:12b', 'llama3.2:3b-instruct-q4', 'qwen3'];

    test('정확 일치', () {
      expect(OllamaClient.hasModel(models, 'gemma4:12b'), isTrue);
    });

    test('태그 생략 시 이름만으로도 찾는다', () {
      expect(OllamaClient.hasModel(models, 'qwen3'), isTrue);
      expect(OllamaClient.hasModel(models, 'gemma4'), isTrue);
    });

    test('없는 모델·빈 이름은 false', () {
      expect(OllamaClient.hasModel(models, 'gpt-oss'), isFalse);
      expect(OllamaClient.hasModel(models, ''), isFalse);
    });
  });
}
