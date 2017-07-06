# Temporal - Date Segment Manipulation

### Date Segment - Align Within Table

[dbo].[DateSegments_AlignWithinTable]

Aligns multi-layered, segmented information within a table by a partition so that each segment will break with evenly. This enables easier aggregation when needing to prioritize information stored across multiple segments within a single partition.