// Offline prüfbar: die Sperrliste. Die Fälle stammen aus der Prüfung der
// Browser-Skills (pruefe-sperrliste.cjs); dazu die Dateibereiche unter
// pluginfile.php und die Gegenprobe gegen die Positivliste der App.
import 'package:flutter_test/flutter_test.dart';
import 'package:moocp/moodle/moodle_zugang.dart';
import 'package:moocp/moodle/sperrliste.dart';
import 'package:moocp/protokoll.dart';

const mussSperren = [
  '/mod/assign/view.php?id=123&action=grading',
  '/mod/assign/view.php?id=123&action=grader&userid=45',
  '/mod/assign/grader.php?id=123',
  '/mod/assign/grade.php?id=123&userid=45',
  '/grade/report/grader/index.php?id=43',
  // Der Notenbereich bleibt gesperrt; die Ausnahme gilt nur den drei
  // Definitionsseiten und dort nur der Regel /grade/.
  '/grade/edit/tree/index.php?id=43',
  '/grade/grading/form/rubric/preview.php?areaid=424',
  '/grade/grading/index.php?areaid=424',
  '/grade/grading/manage.php?contextid=11591&action=grading',
  '/grade/grading/form/rubric/edit.php?areaid=424&action=grader&userid=45',
  '/user/view.php?id=105&course=43',
  '/user/profile.php?id=105',
  '/user/index.php?id=43',
  '/course/user.php?id=43&user=105',
  '/report/log/index.php?id=43',
  '/report/progress/index.php?course=43',
  '/enrol/users.php?id=43',
  '/group/members.php?group=7',
  '/group/index.php?id=43',
  '/group/overview.php?id=43',
  '/mod/quiz/report.php?id=5001&mode=overview',
  '/mod/quiz/review.php?attempt=88',
  '/mod/quiz/attempt.php?attempt=88',
  '/mod/quiz/summary.php?attempt=88',
  '/mod/quiz/startattempt.php?cmid=5001',
  '/mod/quiz/overrides.php?cmid=5001&mode=user',
  '/mod/quiz/overrideedit.php?cmid=5001',
  '/mod/quiz/processattempt.php?attempt=88',
  '/mod/quiz/reviewquestion.php?attempt=88&slot=1',
  '/mod/feedback/show_entries.php?id=5',
  '/mod/choice/report.php?id=5',
  '/mod/forum/user.php?id=105',
  '/mod/h5pactivity/report.php?a=1',
  '/message/index.php',
  '/badges/view.php?type=2&id=43',
  '/admin/plugins.php',
  '/cohort/index.php',
  '/question/bank/comment/comment.php?id=1',
  '/question/type/stack/questiontestreport.php?questionid=5004',
  '/mod/checklist/report.php?id=5008&studentid=45',
  '/mod/checklist/view.php?id=5008&studentid=45',
  '/mod/wiki/history.php?pageid=90',
  '/mod/wiki/diff.php?pageid=90&comparewith=1&compare=2',
  '/mod/wiki/comments.php?pageid=90',
  '/mod/wiki/map.php?pageid=90&option=1',
  '/mod/wiki/map.php?pageid=90&option=6',
  '/mod/wiki/admin.php?pageid=90&option=2',
  '/mod/wiki/view.php?id=5015&uid=45',
  '/mod/wiki/create.php?wid=22&group=0&uid=45&title=x',
  '/mod/wiki/view.php?wid=22&title=Startseite&groupanduser=3-45',
  '/mod/board/export.php?id=5016',
  '/mod/board/download_submissions.php?id=5016',
  '/mod/board/view.php?id=5016&ownerid=45',
  '/mod/kanban/export.php?boardid=7',
  '/mod/kanban/view.php?id=5014&userid=45',
  // Dateien von Personen -- neu in der App, weil sie selbst Dateien holt
  '/pluginfile.php/5/user/icon/boost/f1?rev=1',
  '/pluginfile.php/5/user/private/0/notizen.pdf',
  '/pluginfile.php/5007/assignsubmission_file/submission_files/88/abgabe.pdf',
  '/pluginfile.php/5007/assignsubmission_onlinetext/submissions_onlinetext/88/bild.png',
  '/pluginfile.php/5007/assignfeedback_file/feedback_files/12/korrektur.pdf',
  '/pluginfile.php/5007/assignfeedback_editpdf/download/12/abgabe.pdf',
  '/pluginfile.php/9/question/response_attachments/1/2/3/datei.txt',
  '/pluginfile.php/9/mod_forum/attachment/7/anhang.pdf',
  '/pluginfile.php/9/mod_forum/post/7/bild.png',
  '/pluginfile.php/9/mod_workshop/submission_attachment/7/a.pdf',
  '/pluginfile.php/9/mod_data/content/7/foto.jpg',
  '/pluginfile.php/9/mod_lesson/essay_responses/7/a.png',
];

const mussDurchlassen = [
  '/course/view.php?id=43',
  '/course/modedit.php?add=quiz&course=43&section=4',
  '/course/modedit.php?update=5013',
  '/mod/checklist/view.php?id=5008',
  '/mod/wiki/view.php?id=5015',
  '/mod/wiki/map.php?pageid=90&option=5',
  '/mod/wiki/create.php?action=create&wid=22&group=0&uid=0',
  '/mod/wiki/admin.php?pageid=90&delete=91&option=1&listall=1&sesskey=abc',
  '/mod/board/view.php?id=5016',
  '/mod/board/note_create_ajax.php?columnid=171&ownerid=0&groupid=0',
  '/mod/kanban/view.php?id=5014',
  '/mod/assign/view.php?id=5013',
  '/mod/quiz/edit.php?cmid=5001',
  '/question/edit.php?cmid=5002&cat=11,12',
  '/question/bank/editquestion/question.php?cmid=5002&id=5003',
  '/question/type/stack/questiontestrun.php?questionid=5004&cmid=5002',
  // Bewertungsschemata: die Definition, nicht die Bewertung
  '/grade/grading/manage.php?contextid=11591&component=mod_assign&area=submissions',
  '/grade/grading/form/rubric/edit.php?areaid=424',
  '/grade/grading/form/guide/edit.php?areaid=424',
  '/grade/grading/pick.php?targetid=424',
  '/mod/book/tool/print/index.php?id=2047',
];

/// Was die Werkzeuge der App anfragen. Nichts davon darf gesperrt sein, und
/// die Positivliste muss es durchlassen.
const werkzeugGet = [
  '/login/index.php',
  '/login/index.php?testsession=5',
  '/course/modedit.php?update=15271',
  '/course/modedit.php?add=assign&type=&course=43&section=0&return=0&sr=0',
  '/course/editsection.php?id=812',
  '/filter/manage.php?contextid=11591',
  '/draftfile.php/2393/user/draft/905327642/bild.svg',
  '/pluginfile.php/6520/mod_folder/content/0/a.odt',
  '/pluginfile.php/7000/mod_page/content/3/zeichnung.svg',
  '/pluginfile.php/7001/mod_assign/introattachment/0/vorlage.pdf',
  '/pluginfile.php/7001/mod_assign/intro/bild.png',
  '/pluginfile.php/7449/question/questiontext/1/2/3/bild.png',
  '/question/type/stack/adminui/caschat.php?questionid=5005&cmid=5002',
  '/question/bank/deletequestion/delete.php?cmid=5002&deleteselected=1&deleteall=1&returnurl=%2Fquestion%2Fedit.php%3Fcmid%3D5002&q5006=1&q5009=1',
];

void main() {
  test('Sperrliste sperrt, was Personendaten zeigt', () {
    final durch = [for (final a in mussSperren) if (!gesperrt(Uri.parse(a))) a];
    expect(durch, isEmpty);
  });

  test('Sperrliste lässt Kursinhalte und Bewertungsschemata durch', () {
    final gesperrteDabei = [for (final a in mussDurchlassen) if (gesperrt(Uri.parse(a))) '$a ← ${sperrregel(Uri.parse(a))}'];
    expect(gesperrteDabei, isEmpty);
  });

  test('Gegenprobe: was die Werkzeuge brauchen, ist erlaubt und nicht gesperrt', () {
    final z = MoodleZugang(Protokoll());
    for (final a in werkzeugGet) {
      final u = Uri.parse('https://m.example$a');
      expect(gesperrt(u), isFalse, reason: '$a ← ${sperrregel(u)}');
      expect(z.erlaubt('GET', u), isTrue, reason: a);
    }
  });

  test('Die Positivliste allein ließe Abgaben unter pluginfile.php durch -- darum die Sperrliste', () {
    final z = MoodleZugang(Protokoll());
    final u = Uri.parse('https://m.example/pluginfile.php/5007/assignsubmission_file/submission_files/88/abgabe.pdf');
    expect(z.erlaubt('GET', u), isTrue);
    expect(gesperrt(u), isTrue);
  });

  group('Ausnahme Sicherungsdatei unter user/backup', () {
    const basis = 'https://m.example';

    test('die Sicherung mit forcedownload=1 ist erlaubt, mit und ohne Zahlen-Segment', () {
      for (final a in [
        '/pluginfile.php/5001/user/backup/kurs-k12-2026-10-18_090507.mbz?forcedownload=1',
        '/pluginfile.php/5001/user/backup/12/kurs-k12.mbz?forcedownload=1',
      ]) {
        expect(gesperrt(Uri.parse('$basis$a')), isFalse, reason: a);
      }
    });

    test('andere Nutzerpfade bleiben gesperrt, auch mit forcedownload=1', () {
      for (final a in [
        '/pluginfile.php/5001/user/private/abgabe.mbz?forcedownload=1',
        '/pluginfile.php/5001/user/icon/f1.mbz?forcedownload=1',
        '/pluginfile.php/5001/user/backupx/kurs.mbz?forcedownload=1',
      ]) {
        expect(gesperrt(Uri.parse('$basis$a')), isTrue, reason: a);
      }
    });

    test('andere Dateitypen unter user/backup bleiben gesperrt', () {
      for (final a in [
        '/pluginfile.php/5001/user/backup/notiz.pdf?forcedownload=1',
        '/pluginfile.php/5001/user/backup/liste.zip?forcedownload=1',
        '/pluginfile.php/5001/user/backup/kurs.mbz.html?forcedownload=1',
      ]) {
        expect(gesperrt(Uri.parse('$basis$a')), isTrue, reason: a);
      }
    });

    test('ohne forcedownload=1 bleibt die Sicherung gesperrt', () {
      for (final a in [
        '/pluginfile.php/5001/user/backup/kurs.mbz',
        '/pluginfile.php/5001/user/backup/kurs.mbz?forcedownload=0',
        '/pluginfile.php/5001/user/backup/kurs.mbz?forcedownload=1&x=1',
      ]) {
        expect(gesperrt(Uri.parse('$basis$a')), isTrue, reason: a);
      }
    });

    test('Pfade mit .. bleiben gesperrt, auch wenn sie auf eine Sicherung enden', () {
      for (final a in [
        '/pluginfile.php/5001/user/backup/../private/abgabe.mbz?forcedownload=1',
        '/pluginfile.php/5001/user/backup/../../user/private/kurs.mbz?forcedownload=1',
        '/pluginfile.php/5001/user/backup/%2e%2e/private/kurs.mbz?forcedownload=1',
      ]) {
        expect(gesperrt(Uri.parse('$basis$a')), isTrue, reason: a);
      }
    });
  });

  test('Protokoll ohne Parameterwerte', () {
    expect(adresseOhneWerte(Uri.parse('https://m.example/mod/checklist/view.php?id=5008&studentid=45')),
        '/mod/checklist/view.php?id=…&studentid=…');
    expect(adresseOhneWerte(Uri.parse('https://m.example/user/index.php')), '/user/index.php');
  });

  test('Personenfelder werden entfernt, auch verschachtelt; idnumber bleibt', () {
    final aus = ohnePersonenfelder({
      'itemid': 5,
      'author': 'Erika Mustermann',
      'idnumber': 'LS2-A1',
      'list': [
        {'filename': 'a.pdf', 'author': 'Erika Mustermann', 'userid': 7},
      ],
    });
    expect(aus, isA<Map<String, Object?>>(), reason: 'dateibereiche() prüft genau diesen Typ');
    expect(aus, {
      'itemid': 5,
      'idnumber': 'LS2-A1',
      'list': [
        {'filename': 'a.pdf'},
      ],
    });
  });
}
