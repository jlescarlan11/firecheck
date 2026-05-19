/// Hardcoded fallback list of the 10 RA 9514 occupancy groups. Used when
/// the local Drift `ra_9514_types` table is empty (before the seed
/// populates it).
class Ra9514Entry {
  const Ra9514Entry({required this.code, required this.labelKey});
  final String code;
  final String labelKey; // matches an i18n key like 'ra9514GroupA'
}

const ra9514Fallback = <Ra9514Entry>[
  Ra9514Entry(code: 'A', labelKey: 'ra9514GroupA'),
  Ra9514Entry(code: 'B', labelKey: 'ra9514GroupB'),
  Ra9514Entry(code: 'C', labelKey: 'ra9514GroupC'),
  Ra9514Entry(code: 'D', labelKey: 'ra9514GroupD'),
  Ra9514Entry(code: 'E', labelKey: 'ra9514GroupE'),
  Ra9514Entry(code: 'F', labelKey: 'ra9514GroupF'),
  Ra9514Entry(code: 'G', labelKey: 'ra9514GroupG'),
  Ra9514Entry(code: 'H', labelKey: 'ra9514GroupH'),
  Ra9514Entry(code: 'I', labelKey: 'ra9514GroupI'),
  Ra9514Entry(code: 'J', labelKey: 'ra9514GroupJ'),
];
