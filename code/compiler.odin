package main


PumpAction :: enum
{
    ParsePackage,
    ParseFile,
}

PumpResult :: enum
{
    Continue,
    Error,
}


compiler_pump :: proc( action: PumpAction, file_id: FileID ) -> PumpResult
{
    switch action
    {
        case .ParsePackage:
            return pump_parse_package( file_id )
        case .ParseFile:
            return pump_parse_file( nil, file_id )
    }

    return .Continue
}
