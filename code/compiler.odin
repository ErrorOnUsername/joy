package main


PumpAction :: enum
{
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
        case .ParseFile:
            return pump_parse_file( nil, file_id )
    }

    return .Continue
}
