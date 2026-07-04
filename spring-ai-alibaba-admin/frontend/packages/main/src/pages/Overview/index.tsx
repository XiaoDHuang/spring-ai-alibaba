import React, { useEffect, useState } from 'react';
import { Card, Col, Row, Statistic, Spin, Timeline, Progress, Tag, Typography, Empty } from 'antd';
import {
  BulbOutlined, ExperimentOutlined, DatabaseOutlined, ApiOutlined,
  FileTextOutlined, HistoryOutlined, BranchesOutlined, FileOutlined,
  CheckCircleOutlined,
} from '@ant-design/icons';
import { getOverview, OverviewResponse } from '@/services/overview';

const { Text, Title } = Typography;

const STATUS_COLORS: Record<string, string> = {
  DRAFT: '#d9d9d9', RUNNING: '#1890ff', COMPLETED: '#52c41a',
  FAILED: '#ff4d4f', STOPPED: '#faad14',
};

const ACTIVITY_ICONS: Record<string, React.ReactNode> = {
  prompt_version: <BranchesOutlined />,
  experiment: <ExperimentOutlined />,
  dataset: <DatabaseOutlined />,
};

const OverviewPage: React.FC = () => {
  const [data, setData] = useState<OverviewResponse | null>(null);
  const [loading, setLoading] = useState(true);

  const [errMsg, setErrMsg] = useState('');

  useEffect(() => {
    getOverview()
      .then((res) => {
        if (res?.stats) setData(res);
        else setErrMsg('接口返回无 stats 字段: ' + JSON.stringify(res).substring(0, 200));
      })
      .catch((e) => setErrMsg('请求失败: ' + (e?.message || JSON.stringify(e))))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div style={{ textAlign: 'center', padding: 80 }}><Spin size="large" /></div>;
  if (!data) return <div style={{ padding: 80, textAlign: 'center' }}>
    <Empty description="暂无数据" />
    {errMsg && <Text type="danger" style={{ display: 'block', marginTop: 16 }}>{errMsg}</Text>}
  </div>;

  const { stats, experimentStatus, topPromptVersions, recentActivities, docIndexStatus } = data;

  const expTotal = Object.values(experimentStatus || {}).reduce((a, b) => a + b, 0);

  // Find max for bar chart scaling
  const maxBar = Math.max(
    ...(topPromptVersions || []).flatMap((v) => [v.preCount, v.releaseCount]),
    1
  );

  return (
    <div style={{ padding: 24 }}>
      <Title level={4} style={{ marginBottom: 16 }}>平台总览</Title>

      {/* ── Row 1: 6 Stat Cards ── */}
      <Row gutter={16} style={{ marginBottom: 16 }}>
        {[
          { title: 'Prompt', value: stats.prompts.total, icon: <BulbOutlined />, color: '#722ed1' },
          { title: 'Version', value: stats.versions.total, icon: <BranchesOutlined />, color: '#13c2c2' },
          { title: '实验', value: stats.experiments.total, icon: <ExperimentOutlined />, color: '#1890ff' },
          { title: '数据集', value: stats.datasets.total, icon: <DatabaseOutlined />, color: '#fa8c16' },
          { title: '知识库', value: stats.knowledgeBases.total, icon: <FileTextOutlined />, color: '#52c41a' },
          { title: '模型', value: stats.models.total, icon: <ApiOutlined />, color: '#eb2f96' },
        ].map((item) => (
          <Col span={4} key={item.title}>
            <Card hoverable size="small">
              <Statistic
                title={item.title}
                value={item.value}
                prefix={<span style={{ color: item.color, fontSize: 20 }}>{item.icon}</span>}
              />
            </Card>
          </Col>
        ))}
      </Row>

      {/* ── Row 2: Experiment Pie + Top Versions Bar ── */}
      <Row gutter={16} style={{ marginBottom: 16 }}>
        <Col span={12}>
          <Card title={<><ExperimentOutlined /> 实验状态分布</>} size="small">
            {expTotal === 0 ? (
              <Empty description="暂无实验" />
            ) : (
              <Row gutter={[8, 16]} justify="center">
                {Object.entries(experimentStatus).map(([status, count]) => (
                  <Col key={status} style={{ textAlign: 'center', width: 100 }}>
                    <Progress
                      type="circle"
                      width={80}
                      percent={expTotal > 0 ? Math.round((count / expTotal) * 100) : 0}
                      strokeColor={STATUS_COLORS[status] || '#d9d9d9'}
                      format={() => count}
                    />
                    <div style={{ marginTop: 4 }}>
                      <Tag color={STATUS_COLORS[status]}>{status}</Tag>
                    </div>
                  </Col>
                ))}
              </Row>
            )}
          </Card>
        </Col>
        <Col span={12}>
          <Card title={<><BranchesOutlined /> Top 10 Prompt 版本</>} size="small">
            {(topPromptVersions || []).length === 0 ? (
              <Empty description="暂无版本数据" />
            ) : (
              <div style={{ maxHeight: 280, overflowY: 'auto' }}>
                {(topPromptVersions || []).slice(0, 10).map((v, i) => (
                  <div key={i} style={{ marginBottom: 10 }}>
                    <Text style={{ fontSize: 12, display: 'block', marginBottom: 4 }} ellipsis>
                      {v.promptKey}
                    </Text>
                    <div style={{ display: 'flex', gap: 8, height: 22 }}>
                      <div style={{
                        width: `${Math.round((v.preCount / maxBar) * 100)}%`,
                        minWidth: v.preCount > 0 ? 24 : 0,
                        background: 'linear-gradient(90deg, #faad14, #fa8c16)',
                        borderRadius: 3,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        fontSize: 11, color: '#fff', fontWeight: 600,
                      }}>
                        {v.preCount > 0 ? `pre ${v.preCount}` : ''}
                      </div>
                      <div style={{
                        width: `${Math.round((v.releaseCount / maxBar) * 100)}%`,
                        minWidth: v.releaseCount > 0 ? 24 : 0,
                        background: 'linear-gradient(90deg, #52c41a, #389e0d)',
                        borderRadius: 3,
                        display: 'flex', alignItems: 'center', justifyContent: 'center',
                        fontSize: 11, color: '#fff', fontWeight: 600,
                      }}>
                        {v.releaseCount > 0 ? `release ${v.releaseCount}` : ''}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </Col>
      </Row>

      {/* ── Row 3: Timeline + Doc Index ── */}
      <Row gutter={16}>
        <Col span={12}>
          <Card title={<><HistoryOutlined /> 最近活动</>} size="small">
            {(recentActivities || []).length === 0 ? (
              <Empty description="暂无活动" />
            ) : (
              <Timeline
                items={(recentActivities || []).slice(0, 20).map((a) => ({
                  dot: ACTIVITY_ICONS[a.type] || <FileOutlined />,
                  children: (
                    <div>
                      <Text style={{ fontSize: 13 }}>{a.title}</Text>
                      <div style={{ fontSize: 11, color: '#999' }}>
                        {a.description && <Tag style={{ fontSize: 10 }}>{a.description}</Tag>}
                        {new Date(a.time).toLocaleString()}
                      </div>
                    </div>
                  ),
                }))}
              />
            )}
          </Card>
        </Col>
        <Col span={12}>
          <Card title={<><CheckCircleOutlined /> 文档索引状态</>} size="small">
            {(docIndexStatus || []).length === 0 ? (
              <Empty description="暂无知识库" />
            ) : (
              <div style={{ maxHeight: 280, overflowY: 'auto' }}>
                {(docIndexStatus || []).map((d) => (
                  <div key={d.kbId} style={{ marginBottom: 12 }}>
                    <Text style={{ fontSize: 13, display: 'block' }}>{d.kbName}</Text>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <Progress
                        percent={Math.round(d.progress * 100)}
                        size="small"
                        style={{ flex: 1 }}
                        strokeColor={d.progress >= 1 ? '#52c41a' : '#1890ff'}
                      />
                      <Text style={{ fontSize: 11, color: '#999', whiteSpace: 'nowrap' }}>
                        {d.totalDocs} 篇文档
                      </Text>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </Col>
      </Row>
    </div>
  );
};

export default OverviewPage;
