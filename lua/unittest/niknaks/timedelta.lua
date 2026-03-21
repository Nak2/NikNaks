
return {
    groupname = "TimeDelta",
    init = function()
        Should( _UNITTEST )
            :WithMessage( "Unit test flag not set" )
            .And:BeTrue()

        require( "niknaks" )

        Should( NikNaks.TimeDelta ):Exist()
            .And:BeOfType( "table" )
    end,
    cases = {

        -- ────────────────────────────────────────────────────────────────
        -- Construction
        -- ────────────────────────────────────────────────────────────────

        {
            name = "construct: stores time field",
            func = function()
                local td = NikNaks.TimeDelta( 3600 )
                Should( td ):Exist()
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "construct: zero duration",
            func = function()
                local td = NikNaks.TimeDelta( 0 )
                Should( td.time ):Be( 0 )
            end
        },
        {
            name = "construct: negative duration",
            func = function()
                local td = NikNaks.TimeDelta( -7200 )
                Should( td.time ):Be( -7200 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Getters
        -- ────────────────────────────────────────────────────────────────

        {
            name = "GetSeconds: 3600s = 3600 seconds",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ):GetSeconds() ):Be( 3600 )
            end
        },
        {
            name = "GetMinutes: 3600s = 60 minutes",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ):GetMinutes() ):Be( 60 )
            end
        },
        {
            name = "GetHours: 3600s = 1 hour",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ):GetHours() ):Be( 1 )
            end
        },
        {
            name = "GetHours: 7200s = 2 hours",
            func = function()
                Should( NikNaks.TimeDelta( 7200 ):GetHours() ):Be( 2 )
            end
        },
        {
            name = "GetDays: 86400s = 1 day",
            func = function()
                Should( NikNaks.TimeDelta( 86400 ):GetDays() ):Be( 1 )
            end
        },
        {
            name = "GetWeeks: 604800s = 1 week",
            func = function()
                Should( NikNaks.TimeDelta( 604800 ):GetWeeks() ):Be( 1 )
            end
        },
        {
            name = "GetMiliseconds: 1s = 1000ms",
            func = function()
                Should( NikNaks.TimeDelta( 1 ):GetMiliseconds() ):Be( 1000 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- IsNegative / IsPositive
        -- ────────────────────────────────────────────────────────────────

        {
            name = "IsNegative: true for negative time",
            func = function()
                Should( NikNaks.TimeDelta( -1 ):IsNegative() ):BeTrue()
            end
        },
        {
            name = "IsNegative: false for positive time",
            func = function()
                Should( NikNaks.TimeDelta( 1 ):IsNegative() ):BeFalse()
            end
        },
        {
            name = "IsNegative: false for zero",
            func = function()
                Should( NikNaks.TimeDelta( 0 ):IsNegative() ):BeFalse()
            end
        },
        {
            name = "IsPositive: true for positive time",
            func = function()
                Should( NikNaks.TimeDelta( 100 ):IsPositive() ):BeTrue()
            end
        },
        {
            name = "IsPositive: true for zero",
            func = function()
                Should( NikNaks.TimeDelta( 0 ):IsPositive() ):BeTrue()
            end
        },
        {
            name = "IsPositive: false for negative time",
            func = function()
                Should( NikNaks.TimeDelta( -1 ):IsPositive() ):BeFalse()
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- ToTable
        -- ────────────────────────────────────────────────────────────────

        {
            name = "ToTable: 3661s decomposes into 1 Hour, 1 Minute, 1 Second",
            func = function()
                local t = NikNaks.TimeDelta( 3661 ):ToTable()
                Should( t ):Exist()
                Should( t.Hour ):Be( 1 )
                Should( t.Minute ):Be( 1 )
                Should( t.Second ):Be( 1 )
            end
        },
        {
            name = "ToTable: 86400s is exactly 1 Day",
            func = function()
                local t = NikNaks.TimeDelta( 86400 ):ToTable()
                Should( t.Day ):Be( 1 )
                Should( t.Hour ):BeNil()
                Should( t.Minute ):BeNil()
            end
        },
        {
            name = "ToTable: result is cached (same table reference on second call)",
            func = function()
                local td = NikNaks.TimeDelta( 3600 )
                Should( td:ToTable() ):Be( td:ToTable() )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- __tostring
        -- ────────────────────────────────────────────────────────────────

        {
            name = "tostring: 3661s = '1 Hour, 1 Minute and 1 Second'",
            func = function()
                Should( tostring( NikNaks.TimeDelta( 3661 ) ) ):Be( "1 Hour, 1 Minute and 1 Second" )
            end
        },
        {
            name = "tostring: 7200s = '2 Hours'",
            func = function()
                Should( tostring( NikNaks.TimeDelta( 7200 ) ) ):Be( "2 Hours" )
            end
        },
        {
            name = "tostring: 0s = 'nil'",
            func = function()
                Should( tostring( NikNaks.TimeDelta( 0 ) ) ):Be( "nil" )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Arithmetic operators
        -- ────────────────────────────────────────────────────────────────

        {
            name = "add number: timedelta + 3600 increases time by 3600",
            func = function()
                local result = NikNaks.TimeDelta( 3600 ) + 3600
                Should( result.time ):Be( 7200 )
            end
        },
        {
            name = "sub number: timedelta - 1800 decreases time by 1800",
            func = function()
                local result = NikNaks.TimeDelta( 3600 ) - 1800
                Should( result.time ):Be( 1800 )
            end
        },
        {
            name = "mul: timedelta * 3 triples the duration",
            func = function()
                local result = NikNaks.TimeDelta( 3600 ) * 3
                Should( result.time ):Be( 10800 )
            end
        },
        {
            name = "div: timedelta / 2 halves the duration",
            func = function()
                local result = NikNaks.TimeDelta( 3600 ) / 2
                Should( result.time ):Be( 1800 )
            end
        },
        {
            name = "mod: 3661s % 60 = 1 (leftover seconds after full minutes)",
            func = function()
                local result = NikNaks.TimeDelta( 3661 ) % 60
                Should( result.time ):Be( 1 )
            end
        },
        {
            name = "pow: timedelta ^ 2 squares the duration in seconds",
            func = function()
                local result = NikNaks.TimeDelta( 10 ) ^ 2
                Should( result.time ):Be( 100 )
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Comparison operators
        -- ────────────────────────────────────────────────────────────────

        {
            name = "eq: same duration is equal",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ) == NikNaks.TimeDelta( 3600 ) ):BeTrue()
            end
        },
        {
            name = "eq: different durations are not equal",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ) == NikNaks.TimeDelta( 7200 ) ):BeFalse()
            end
        },
        {
            name = "lt: shorter duration is less than longer",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ) < NikNaks.TimeDelta( 7200 ) ):BeTrue()
            end
        },
        {
            name = "lt: longer duration is not less than shorter",
            func = function()
                Should( NikNaks.TimeDelta( 7200 ) < NikNaks.TimeDelta( 3600 ) ):BeFalse()
            end
        },
        {
            name = "le: equal duration satisfies <=",
            func = function()
                Should( NikNaks.TimeDelta( 3600 ) <= NikNaks.TimeDelta( 3600 ) ):BeTrue()
            end
        },
        {
            name = "le: shorter satisfies <=",
            func = function()
                Should( NikNaks.TimeDelta( 1800 ) <= NikNaks.TimeDelta( 3600 ) ):BeTrue()
            end
        },

        -- ────────────────────────────────────────────────────────────────
        -- Add / Sub helper methods
        -- ────────────────────────────────────────────────────────────────

        {
            name = "AddSeconds: adds correct number of seconds",
            func = function()
                local td = NikNaks.TimeDelta( 0 ):AddSeconds( 90 )
                Should( td.time ):Be( 90 )
            end
        },
        {
            name = "AddMinutes: adds correct number of seconds",
            func = function()
                local td = NikNaks.TimeDelta( 0 ):AddMinutes( 2 )
                Should( td.time ):Be( 120 )
            end
        },
        {
            name = "AddHours: adds correct number of seconds",
            func = function()
                local td = NikNaks.TimeDelta( 0 ):AddHours( 1 )
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "AddDays: adds correct number of seconds",
            func = function()
                local td = NikNaks.TimeDelta( 0 ):AddDays( 1 )
                Should( td.time ):Be( 86400 )
            end
        },
        {
            name = "SubSeconds: subtracts correct number of seconds",
            func = function()
                local td = NikNaks.TimeDelta( 3600 ):SubSeconds( 600 )
                Should( td.time ):Be( 3000 )
            end
        },
        {
            name = "SubHours: subtracts correct number of seconds",
            func = function()
                local td = NikNaks.TimeDelta( 7200 ):SubHours( 1 )
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "Add then Sub returns original duration",
            func = function()
                local td = NikNaks.TimeDelta( 3600 ):AddHours( 2 ):SubHours( 2 )
                Should( td.time ):Be( 3600 )
            end
        },
        {
            name = "AddHours: ToTable reflects updated duration after mutation",
            func = function()
                local td = NikNaks.TimeDelta( 3600 )
                Should( td:ToTable().Hour ):Be( 1 )
                td:AddHours( 1 )
                Should( td:ToTable().Hour ):Be( 2 )
            end
        },
    }
}
