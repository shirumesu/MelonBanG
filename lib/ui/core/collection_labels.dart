import '../../domain/catalog.dart';

const collectionLabels = {
  CollectionStatus.watching: '在看',
  CollectionStatus.wish: '想看',
  CollectionStatus.completed: '看过',
  CollectionStatus.onHold: '搁置',
  CollectionStatus.dropped: '抛弃',
};

/// Bangumi's wording for personal scores 1–10.
const scoreLabels = [
  '',
  '不忍直视',
  '很差',
  '差',
  '较差',
  '不过不失',
  '还行',
  '推荐',
  '力荐',
  '神作',
  '超神作',
];
