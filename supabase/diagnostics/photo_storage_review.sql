-- Read-only predeployment review. Run as an authorized database operator.
-- Never infer ownership from storage owner/owner_id, or delete based on this
-- output. Missing metadata can be a valid upload awaiting registration.
-- Output is capped at 500; total_flagged reports whether more remain.
with parsed as (
  select o.id, o.name, o.created_at,
    regexp_match(o.name,
      '^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jpg$') parts
  from storage.objects o where o.bucket_id = 'photos'
), reviewed as (
  select o.id, o.name, o.created_at, s.id submission_id,
    s.submitted_by canonical_author, f.assignment_id,
    array_remove(array[
      case when o.parts is null then 'noncanonical_path' end,
      case when o.parts is not null and s.id is null then 'missing_submission' end,
      case when s.id is not null and (s.submitted_by is null or u.id is null) then 'missing_canonical_author' end,
      case when s.id is not null and (f.id is null or a.id is null) then 'missing_feature_or_assignment' end,
      case when s.id is not null and not exists (
        select 1 from public.assignment_members m
        where m.assignment_id = f.assignment_id and m.enumerator_id = s.submitted_by
      ) then 'author_not_current_member' end,
      case when o.parts is not null and p.id is null then 'unregistered_upload_review_pending' end,
      case when p.id is not null and (p.submission_id is distinct from s.id or p.storage_path is distinct from o.name)
        then 'photo_uuid_binding_mismatch' end,
      case when exists (
        select 1 from public.photos linked where linked.storage_path = o.name
          and (linked.id is distinct from (o.parts)[2]::uuid or linked.submission_id is distinct from s.id)
      ) then 'metadata_path_binding_mismatch' end
    ], null) reasons
  from parsed o
  left join public.submissions s on s.id = (o.parts)[1]::uuid
  left join auth.users u on u.id = s.submitted_by
  left join public.features f on f.id = s.feature_id
  left join public.assignments a on a.id = f.assignment_id
  left join public.photos p on p.id = (o.parts)[2]::uuid
)
select id, name, created_at, submission_id, canonical_author, assignment_id,
  reasons, count(*) over () total_flagged
from reviewed where cardinality(reasons) > 0
order by created_at, id
limit 500;
