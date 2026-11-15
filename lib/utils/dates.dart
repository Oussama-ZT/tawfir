DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

DateTime addMonths(DateTime d, int months) => DateTime(d.year, d.month + months);

int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
