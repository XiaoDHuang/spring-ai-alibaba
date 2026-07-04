import { request } from '@/legacy/utils/request';

function getToken(): string {
  try {
    const raw = localStorage.getItem('data-prefers-session');
    if (!raw) return '';
    return JSON.parse(raw).access_token || '';
  } catch { return ''; }
}

export interface StatItem {
  total: number;
}

export interface OverviewStats {
  prompts: StatItem;
  versions: StatItem;
  experiments: StatItem;
  datasets: StatItem;
  knowledgeBases: StatItem;
  models: StatItem;
}

export interface TopPromptVersion {
  promptKey: string;
  preCount: number;
  releaseCount: number;
}

export interface RecentActivity {
  type: 'prompt_version' | 'experiment' | 'dataset';
  title: string;
  time: number;
  description: string;
}

export interface DocIndexStatus {
  kbId: string;
  kbName: string;
  totalDocs: number;
  indexedDocs: number;
  progress: number;
}

export interface OverviewResponse {
  stats: OverviewStats;
  experimentStatus: Record<string, number>;
  topPromptVersions: TopPromptVersion[];
  recentActivities: RecentActivity[];
  docIndexStatus: DocIndexStatus[];
}

interface ApiResponse<T> { code: number; data: T; }

export async function getOverview(): Promise<OverviewResponse> {
  const token = getToken();
  const res = await request<ApiResponse<OverviewResponse>>('/console/v1/overview', {
    method: 'GET',
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  return (res as any)?.data ?? (res as any);
}
