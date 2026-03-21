
-- Fixed unix timestamps used throughout to keep tests timezone-independent.
-- T1 = 1000000000  (Sep 09 2001 01:46:40 UTC)
-- T2 = 1000003600  (T1 + 1 hour)
local T1 = 1000000000
local T2 = T1 + 3600

return {
    groupname = "DateTime",
    init = function()
        Should( _UNITTEST )
            :WithMessage( "Unit test flag not set" )
            .And:BeTrue()

        require( "niknaks" )

        Should( NikNaks.DateTime ):Exist()
            .And:BeOfType( "table" )
        Should( NikNaks.TimeDelta ):Exist()
            .And:BeOfType( "table" )
    end,
    cases = {

        -- ────────────────────────────────────────────────────────────────
        -- Construction
        -- ────────────────────────────────────────────────────────────────

        {
            name = "construct: from unix number stores correct unix field",
            func = function()
                local dt = NikNaks.DateTime( T1 )
                Should( dt ):Exist()
                Should( dt.unix ):Be( T1 )
            end
        },
        {
            name = "construct: no argument uses current time",
            func = function()
                local dt = NikNaks.DateTime()
                Should( dt ):Exist()
                Should( dt.unix ):BeOfType( "number" )
            end
        },
        {
            name = "construct: invalid type returns nil",
            func = function()
                Should( NikNaks.DateTime( true ) ):BeNil()
            end
        },
        {
            name = "construct: from string (decimal year only)",
            func = function()
                local dt = NikNaks.DateTime( "2001" )
                Should( dt ):Exist()
                Should( dt.unix ):BeOfType( "number" )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- GetUnix
        -- ────────────────────────────────────────────────────────────────

        {
            name = "GetUnix: returns stored unix timestamp",
            func = function()
                Should( NikNaks.DateTime( T1 ):GetUnix() ):Be( T1 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- now / today / yesterday / tomorrow
        -- ────────────────────────────────────────────────────────────────

        {
            name = "DateTime.now: is a DateTime with a unix field",
            func = function()
                local now = NikNaks.DateTime.now
                Should( now ):Exist()
                Should( now.unix ):BeOfType( "number" )
            end
        },
        {
            name = "DateTime.today: same as now (identical second or within 1s)",
            func = function()
                local today = NikNaks.DateTime.today
                Should( today ):Exist()
                Should( today.unix ):BeOfType( "number" )
            end
        },
        {
            name = "DateTime.yesterday: unix is exactly one day before today",
            func = function()
                local diff = NikNaks.DateTime.today.unix - NikNaks.DateTime.yesterday.unix
                Should( diff ):Be( NikNaks.TimeDelta.Day )
            end
        },
        {
            name = "DateTime.tomorrow: unix is exactly one day after today",
            func = function()
                local diff = NikNaks.DateTime.tomorrow.unix - NikNaks.DateTime.today.unix
                Should( diff ):Be( NikNaks.TimeDelta.Day )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- TimeUntil
        -- ────────────────────────────────────────────────────────────────

        {
            name = "TimeUntil: number target returns correct TimeDelta",
            func = function()
                local td = NikNaks.DateTime( T1 ):TimeUntil( T2 )
                Should( td ):Exist()
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "TimeUntil: DateTime target returns correct TimeDelta",
            func = function()
                local td = NikNaks.DateTime( T1 ):TimeUntil( NikNaks.DateTime( T2 ) )
                Should( td ):Exist()
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "TimeUntil: past target returns negative TimeDelta",
            func = function()
                local td = NikNaks.DateTime( T2 ):TimeUntil( T1 )
                Should( td.time ):Be( -3600 )
                Should( td:IsNegative() ):BeTrue()
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Arithmetic
        -- ────────────────────────────────────────────────────────────────

        {
            name = "add number: DateTime + seconds shifts unix forward",
            func = function()
                local result = NikNaks.DateTime( T1 ) + 3600
                Should( result.unix ):Be( T2 )
            end
        },
        {
            name = "sub number: DateTime - seconds shifts unix backward",
            func = function()
                local result = NikNaks.DateTime( T2 ) - 3600
                Should( result.unix ):Be( T1 )
            end
        },
        {
            name = "sub DateTime: two DateTimes produce a TimeDelta",
            func = function()
                local td = NikNaks.DateTime( T2 ) - NikNaks.DateTime( T1 )
                Should( td ):Exist()
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "add TimeDelta: DateTime + TimeDelta shifts unix forward",
            func = function()
                local result = NikNaks.DateTime( T1 ) + NikNaks.TimeDelta( 3600 )
                Should( result.unix ):Be( T2 )
            end
        },
        {
            name = "sub TimeDelta: DateTime - TimeDelta shifts unix backward",
            func = function()
                local result = NikNaks.DateTime( T2 ) - NikNaks.TimeDelta( 3600 )
                Should( result.unix ):Be( T1 )
            end
        },
        {
            name = "add then sub is identity",
            func = function()
                local result = NikNaks.DateTime( T1 ) + 86400 - 86400
                Should( result.unix ):Be( T1 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Comparison
        -- ────────────────────────────────────────────────────────────────

        {
            name = "eq: same unix is equal",
            func = function()
                Should( NikNaks.DateTime( T1 ) == NikNaks.DateTime( T1 ) ):BeTrue()
            end
        },
        {
            name = "eq: different unix is not equal",
            func = function()
                Should( NikNaks.DateTime( T1 ) == NikNaks.DateTime( T2 ) ):BeFalse()
            end
        },
        {
            name = "lt: earlier DateTime is less than later",
            func = function()
                Should( NikNaks.DateTime( T1 ) < NikNaks.DateTime( T2 ) ):BeTrue()
            end
        },
        {
            name = "lt: later DateTime is not less than earlier",
            func = function()
                Should( NikNaks.DateTime( T2 ) < NikNaks.DateTime( T1 ) ):BeFalse()
            end
        },
        {
            name = "le: equal DateTime satisfies <=",
            func = function()
                Should( NikNaks.DateTime( T1 ) <= NikNaks.DateTime( T1 ) ):BeTrue()
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- ToDate
        -- ────────────────────────────────────────────────────────────────

        {
            name = "ToDate: returns a string for any format",
            func = function()
                local s = NikNaks.DateTime( T1 ):ToDate( "%Y" )
                Should( s ):BeOfType( "string" )
                Should( #s ):BeGreaterThan( 0 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- IsLeapYear
        -- ────────────────────────────────────────────────────────────────

        {
            name = "IsLeapYear: 2000 is a leap year (divisible by 400)",
            func = function()
                Should( NikNaks.DateTime.IsLeapYear( 2000 ) ):BeTrue()
            end
        },
        {
            name = "IsLeapYear: 1900 is not a leap year (divisible by 100, not 400)",
            func = function()
                Should( NikNaks.DateTime.IsLeapYear( 1900 ) ):BeFalse()
            end
        },
        {
            name = "IsLeapYear: 2024 is a leap year (divisible by 4, not 100)",
            func = function()
                Should( NikNaks.DateTime.IsLeapYear( 2024 ) ):BeTrue()
            end
        },
        {
            name = "IsLeapYear: 2023 is not a leap year",
            func = function()
                Should( NikNaks.DateTime.IsLeapYear( 2023 ) ):BeFalse()
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- DaysInMonth
        -- ────────────────────────────────────────────────────────────────

        {
            name = "DaysInMonth: February in leap year = 29",
            func = function()
                Should( NikNaks.DateTime.DaysInMonth( 2, 2000 ) ):Be( 29 )
            end
        },
        {
            name = "DaysInMonth: February in non-leap year = 28",
            func = function()
                Should( NikNaks.DateTime.DaysInMonth( 2, 2023 ) ):Be( 28 )
            end
        },
        {
            name = "DaysInMonth: January = 31",
            func = function()
                Should( NikNaks.DateTime.DaysInMonth( 1, 2023 ) ):Be( 31 )
            end
        },
        {
            name = "DaysInMonth: April = 30",
            func = function()
                Should( NikNaks.DateTime.DaysInMonth( 4, 2023 ) ):Be( 30 )
            end
        },
        {
            name = "DaysInMonth: December = 31",
            func = function()
                Should( NikNaks.DateTime.DaysInMonth( 12, 2023 ) ):Be( 31 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Calendar
        -- ────────────────────────────────────────────────────────────────

        {
            name = "Calendar: returns table with year and month fields",
            func = function()
                local c = NikNaks.DateTime.Calendar( 2023 )
                Should( c ):Exist()
                Should( c.year ):Be( 2023 )
                Should( c.month ):BeOfType( "table" )
            end
        },
        {
            name = "Calendar: month table has 12 entries",
            func = function()
                local c = NikNaks.DateTime.Calendar( 2023 )
                Should( #c.month ):Be( 12 )
            end
        },
        {
            name = "Calendar: February = 29 in leap year 2000",
            func = function()
                local c = NikNaks.DateTime.Calendar( 2000 )
                Should( c.month[2] ):Be( 29 )
            end
        },
        {
            name = "Calendar: February = 28 in non-leap year 2023",
            func = function()
                local c = NikNaks.DateTime.Calendar( 2023 )
                Should( c.month[2] ):Be( 28 )
            end
        },
    }
}
