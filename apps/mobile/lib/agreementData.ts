import { supabase } from './supabase';
import type { MobileProfile } from './mobileData';

export type EmployeeAgreement = {
  id: string;
  membershipId: string;
  agreementNo: string;
  title: string;
  status: 'draft' | 'pending_approval' | 'published' | 'accepted' | 'rejected' | 'superseded' | 'expired' | 'revoked';
  effectiveFrom: string;
  effectiveTo: string | null;
  currentVersionId: string | null;
  currentVersionNo: number;
  version: EmployeeAgreementVersion | null;
  response: { response: 'accepted' | 'rejected'; note: string | null; respondedAt: string } | null;
};
export type EmployeeAgreementVersion = { id: string; versionNo: number; title: string; terms: Record<string, unknown>; contentHash: string; status: string; publishedAt: string | null };
export type AgreementMember = { id: string; displayName: string; employeeNo: string | null };

function client() { if (!supabase) throw new Error('supabase_unavailable'); return supabase; }

export async function listEmployeeAgreements(profile: MobileProfile): Promise<EmployeeAgreement[]> {
  const db = client();
  const { data: agreements, error } = await db.from('employee_agreements').select('id,membership_id,agreement_no,title,status,effective_from,effective_to,current_version_id,current_version_no').eq('organization_id', profile.institutionId).order('updated_at', { ascending: false }).limit(100);
  if (error) throw error;
  const rows = (agreements ?? []) as Array<Record<string, unknown>>;
  const versionIds = rows.map((row) => row.current_version_id).filter((id): id is string => typeof id === 'string');
  const agreementIds = rows.map((row) => row.id).filter((id): id is string => typeof id === 'string');
  const [versionsResult, responsesResult] = await Promise.all([
    versionIds.length ? db.from('employee_agreement_versions').select('id,agreement_id,version_no,title,terms,content_hash,status,published_at').in('id', versionIds).limit(100) : Promise.resolve({ data: [], error: null }),
    agreementIds.length ? db.from('employee_agreement_responses').select('agreement_id,version_id,response,note,responded_at').in('agreement_id', agreementIds).eq('membership_id', profile.id).limit(100) : Promise.resolve({ data: [], error: null }),
  ]);
  if (versionsResult.error) throw versionsResult.error;
  if (responsesResult.error) throw responsesResult.error;
  const versions = new Map((versionsResult.data ?? []).map((row) => [row.id, { id: row.id, versionNo: row.version_no, title: row.title, terms: (row.terms ?? {}) as Record<string, unknown>, contentHash: row.content_hash, status: row.status, publishedAt: row.published_at }]));
  const responses = new Map((responsesResult.data ?? []).map((row) => [row.version_id, { response: row.response, note: row.note, respondedAt: row.responded_at }]));
  return rows.map((row) => ({ id: String(row.id), membershipId: String(row.membership_id), agreementNo: String(row.agreement_no), title: String(row.title), status: row.status as EmployeeAgreement['status'], effectiveFrom: String(row.effective_from), effectiveTo: (row.effective_to as string | null) ?? null, currentVersionId: (row.current_version_id as string | null) ?? null, currentVersionNo: Number(row.current_version_no ?? 1), version: typeof row.current_version_id === 'string' ? versions.get(row.current_version_id) ?? null : null, response: typeof row.current_version_id === 'string' ? responses.get(row.current_version_id) ?? null : null }));
}

export async function listAgreementMembers(profile: MobileProfile): Promise<AgreementMember[]> {
  const { data, error } = await client().from('organization_memberships').select('id,display_name,employee_no').eq('organization_id', profile.institutionId).eq('is_active', true).order('display_name').limit(500);
  if (error) throw error;
  return (data ?? []).map((row) => ({ id: row.id, displayName: row.display_name, employeeNo: row.employee_no }));
}

export async function createEmployeeAgreement(input: { organizationId: string; membershipId: string; agreementNo: string; title: string; terms: Record<string, unknown>; effectiveFrom: string; effectiveTo?: string | null }) {
  const { data, error } = await client().rpc('create_employee_agreement', { p_organization_id: input.organizationId, p_membership_id: input.membershipId, p_agreement_no: input.agreementNo, p_title: input.title, p_terms: input.terms, p_effective_from: input.effectiveFrom, p_effective_to: input.effectiveTo ?? null });
  if (error) throw error;
  return data as { agreement_id: string; version_id: string; status: string };
}
export async function submitEmployeeAgreementForApproval(agreementId: string) { const { error } = await client().rpc('submit_employee_agreement_for_approval', { p_agreement_id: agreementId }); if (error) throw error; }
export async function publishEmployeeAgreement(agreementId: string) { const { error } = await client().rpc('publish_employee_agreement', { p_agreement_id: agreementId }); if (error) throw error; }
export async function respondEmployeeAgreement(versionId: string, response: 'accepted' | 'rejected', note: string | null) { const { error } = await client().rpc('respond_employee_agreement', { p_version_id: versionId, p_response: response, p_note: note }); if (error) throw error; }
