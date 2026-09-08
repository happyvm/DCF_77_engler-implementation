// SPDX-License-Identifier: MIT
package dcf77_calendar_pkg;
    function automatic logic leap_year(input logic [7:0] year);
        // DCF77 carries 00..99 and uses the Gregorian 2000..2099 epoch.
        leap_year = (year[1:0] == 2'b00);
    endfunction
    function automatic logic [5:0] month_length(input logic [7:0] year,
                                                  input logic [3:0] month);
        case (month)
          4, 6, 9, 11: month_length = 30;
          2: month_length = leap_year(year) ? 29 : 28;
          default: month_length = 31;
        endcase
    endfunction
    function automatic logic valid_date(input logic [7:0] year,
                                          input logic [3:0] month,
                                          input logic [5:0] day);
        valid_date = month >= 1 && month <= 12 && day >= 1 &&
                     day <= month_length(year, month);
    endfunction
    // European rule: the offset changes on the last Sunday of March/October.
    function automatic logic legal_zone_transition(input logic [3:0] month,
                                                     input logic [5:0] day,
                                                     input logic [2:0] weekday,
                                                     input logic [4:0] hour,
                                                     input logic old_cest,
                                                     input logic new_cest);
        logic last_sunday;
        begin
            last_sunday = weekday == 7 && day >= 25;
            legal_zone_transition = old_cest == new_cest ||
                (!old_cest && new_cest && month == 3 && last_sunday && hour == 2) ||
                ( old_cest && !new_cest && month == 10 && last_sunday && hour == 3);
        end
    endfunction
endpackage
