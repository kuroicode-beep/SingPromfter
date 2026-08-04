// file: test/constants/voice_clips_test.dart
//
// TTS 클립 정본 검증 — id 유일성, 경로 형식, 스텝·코스·단축키 클립 완전성.
import 'package:flutter_test/flutter_test.dart';
import 'package:singpromfter_app/constants/app_shortcuts.dart';
import 'package:singpromfter_app/constants/voice_clips.dart';
import 'package:singpromfter_app/models/vocal_course.dart';
import 'package:singpromfter_app/models/vocal_routine.dart';

void main() {
  test('클립 id는 유일하고 텍스트는 비어 있지 않다', () {
    final ids = <String>{};
    for (final clip in VoiceClips.all) {
      expect(ids.add(clip.id), isTrue, reason: '중복 id: ${clip.id}');
      expect(clip.text.trim(), isNotEmpty, reason: '${clip.id} 텍스트 없음');
      // 파일명으로 쓰이므로 안전한 문자만.
      expect(RegExp(r'^[a-z0-9_\-]+$').hasMatch(clip.id), isTrue,
          reason: '파일명 부적합 id: ${clip.id}');
    }
  });

  test('assetPath는 audio/tts/<id>.wav 형식', () {
    expect(VoiceClips.assetPath('abc'), 'audio/tts/abc.wav');
  });

  test('모든 루틴 스텝(17)에 안내 클립이 있다', () {
    for (final routine in VocalRoutines.all) {
      for (final step in routine.steps) {
        expect(VoiceClips.byId(VoiceClips.stepClipId(step.id)), isNotNull,
            reason: '스텝 클립 누락: ${step.id}');
      }
    }
  });

  test('코스 4주 브리핑 클립이 전부 있다', () {
    for (final week in VocalCourse.weeks) {
      expect(
        VoiceClips.byId(VoiceClips.courseWeekClipId(week.number)),
        isNotNull,
        reason: '주차 클립 누락: ${week.number}',
      );
    }
  });

  test('단축키 항목별 클립이 전부 있다(트레이닝 포함)', () {
    for (final entry in [
      ...AppShortcuts.entries,
      ...AppShortcuts.trainingEntries,
    ]) {
      expect(VoiceClips.byId(entry.clipId), isNotNull,
          reason: '단축키 클립 누락: ${entry.clipId}');
    }
    expect(VoiceClips.byId('help_intro'), isNotNull);
    expect(VoiceClips.byId('help_training_intro'), isNotNull);
    expect(VoiceClips.byId('help_done'), isNotNull);
  });
}
