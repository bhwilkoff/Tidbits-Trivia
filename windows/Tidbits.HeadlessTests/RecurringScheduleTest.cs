using System;
using System.Collections.Generic;
using Tidbits.Core.Models;
using Tidbits.Core.Networking;
using Xunit;

public class RecurringScheduleTest
{
    [Fact]
    public void Next_occurrence_counts_today_and_wraps_the_week()
    {
        var wed = new DateTime(2026, 7, 8); // a Wednesday
        Assert.Equal(new DateTime(2026, 7, 8), RecurringSchedule.NextOccurrence(DayOfWeek.Wednesday, wed)); // today
        Assert.Equal(new DateTime(2026, 7, 10), RecurringSchedule.NextOccurrence(DayOfWeek.Friday, wed));    // +2
        Assert.Equal(new DateTime(2026, 7, 14), RecurringSchedule.NextOccurrence(DayOfWeek.Tuesday, wed));   // wraps to next week
        Assert.Equal("Every Friday · next Jul 10", RecurringSchedule.Display(DayOfWeek.Friday, wed));
    }

    [Fact]
    public void Event_recurring_flag_and_schedule_line()
    {
        var oneOff = new LiveEvent { Rounds = new List<NightRound> { new() { Kind = GameMode.Classic, Count = 5 } } };
        Assert.False(oneOff.IsRecurring);
        Assert.Equal("", oneOff.ScheduleLine(new DateTime(2026, 7, 8)));

        var weekly = oneOff with { Weekday = 5 }; // Friday (DayOfWeek 5)
        Assert.True(weekly.IsRecurring);
        Assert.Equal("Every Friday · next Jul 10", weekly.ScheduleLine(new DateTime(2026, 7, 8)));
    }
}
