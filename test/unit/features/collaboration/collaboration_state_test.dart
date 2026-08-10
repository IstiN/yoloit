import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/collaboration/bloc/collaboration_state.dart';

void main() {
  group('PeerInfo equality', () {
    const peer = PeerInfo(id: 'p1', name: 'Ada', color: '#60A5FA');

    test('is equal to itself and to an identical copy', () {
      expect(peer == peer, isTrue);
      expect(
        peer,
        const PeerInfo(id: 'p1', name: 'Ada', color: '#60A5FA'),
      );
      expect(
        peer.hashCode,
        const PeerInfo(id: 'p1', name: 'Ada', color: '#60A5FA').hashCode,
      );
    });

    test('differs when any field differs', () {
      expect(
        peer == const PeerInfo(id: 'p2', name: 'Ada', color: '#60A5FA'),
        isFalse,
      );
      expect(
        peer == const PeerInfo(id: 'p1', name: 'Bob', color: '#60A5FA'),
        isFalse,
      );
      expect(
        peer == const PeerInfo(id: 'p1', name: 'Ada', color: '#FF0000'),
        isFalse,
      );
    });

    test('is not equal to other types', () {
      // ignore: unrelated_type_equality_checks -- exercising == directly
      expect(peer == 'p1', isFalse);
    });

    test('copyWith overrides only the given fields', () {
      final renamed = peer.copyWith(name: 'Grace');
      expect(renamed.id, 'p1');
      expect(renamed.name, 'Grace');
      expect(renamed.color, '#60A5FA');
      expect(renamed == peer, isFalse);

      final recolored = peer.copyWith(color: '#00FF00');
      expect(recolored.color, '#00FF00');
    });
  });

  group('CollaborationState', () {
    test('convenience getters reflect the mode', () {
      const idle = CollaborationState();
      expect(idle.isIdle, isTrue);
      expect(idle.isHosting, isFalse);
      expect(idle.isGuest, isFalse);

      const hosting = CollaborationState(mode: CollaborationMode.hosting);
      expect(hosting.isHosting, isTrue);
      expect(hosting.isIdle, isFalse);

      const guest = CollaborationState(mode: CollaborationMode.connected);
      expect(guest.isGuest, isTrue);

      const starting = CollaborationState(startingHost: true);
      expect(starting.isStartingHost, isTrue);
      expect(starting.isIdle, isFalse);
    });

    test('copyWith carries over and overrides fields', () {
      const base = CollaborationState(
        mode: CollaborationMode.hosting,
        address: '192.168.1.10:40401',
        peers: {'p1': PeerInfo(id: 'p1', name: 'Ada', color: '#60A5FA')},
      );

      final copy = base.copyWith(peerCount: 1, encryptionEnabled: true);
      expect(copy.mode, CollaborationMode.hosting);
      expect(copy.address, '192.168.1.10:40401');
      expect(copy.peers.keys, ['p1']);
      expect(copy.peerCount, 1);
      expect(copy.encryptionEnabled, isTrue);
    });
  });
}
