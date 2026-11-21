import {
  CreateBucketCommand,
  DeleteObjectCommand,
  GetObjectCommand,
  HeadBucketCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from './env';

export interface ObjectStorageService {
  ensureBucketExists(): Promise<void>;
  putObject(params: {
    key: string;
    body: Buffer;
    contentType: string;
    metadata?: Record<string, string>;
  }): Promise<void>;
  deleteObject(key: string): Promise<void>;
  getSignedDownloadUrl(key: string, expiresInSeconds?: number, internal?: boolean): Promise<string>;
  getSignedUploadUrl(key: string, contentType: string, expiresInSeconds?: number): Promise<string>;
}

class S3ObjectStorageService implements ObjectStorageService {
  private readonly internalClient: S3Client;
  private readonly publicClient: S3Client;
  private bucketEnsured = false;

  constructor() {
    const credentials = {
      accessKeyId: env.S3_ACCESS_KEY_ID,
      secretAccessKey: env.S3_SECRET_ACCESS_KEY,
    };

    this.internalClient = new S3Client({
      endpoint: env.S3_ENDPOINT,
      region: env.S3_REGION,
      forcePathStyle: env.S3_FORCE_PATH_STYLE,
      credentials,
    });

    this.publicClient = new S3Client({
      endpoint: env.S3_PUBLIC_ENDPOINT,
      region: env.S3_REGION,
      forcePathStyle: env.S3_FORCE_PATH_STYLE,
      credentials,
    });
  }

  async ensureBucketExists(): Promise<void> {
    if (this.bucketEnsured) return;
    try {
      await this.internalClient.send(new HeadBucketCommand({ Bucket: env.S3_BUCKET }));
      this.bucketEnsured = true;
    } catch {
      await this.internalClient.send(new CreateBucketCommand({ Bucket: env.S3_BUCKET })).catch(() => undefined);
      this.bucketEnsured = true;
    }
  }

  async putObject(params: {
    key: string;
    body: Buffer;
    contentType: string;
    metadata?: Record<string, string>;
  }): Promise<void> {
    await this.ensureBucketExists();
    await this.internalClient.send(
      new PutObjectCommand({
        Bucket: env.S3_BUCKET,
        Key: params.key,
        Body: params.body,
        ContentType: params.contentType,
        Metadata: params.metadata,
      }),
    );
  }

  async deleteObject(key: string): Promise<void> {
    await this.internalClient.send(
      new DeleteObjectCommand({
        Bucket: env.S3_BUCKET,
        Key: key,
      }),
    );
  }

  async getSignedDownloadUrl(key: string, expiresInSeconds = 300, internal = false): Promise<string> {
    const client = internal ? this.internalClient : this.publicClient;
    return getSignedUrl(
      client,
      new GetObjectCommand({
        Bucket: env.S3_BUCKET,
        Key: key,
      }),
      { expiresIn: expiresInSeconds },
    );
  }

  async getSignedUploadUrl(key: string, contentType: string, expiresInSeconds = 300): Promise<string> {
    return getSignedUrl(
      this.internalClient,
      new PutObjectCommand({
        Bucket: env.S3_BUCKET,
        Key: key,
        ContentType: contentType,
      }),
      { expiresIn: expiresInSeconds },
    );
  }
}

export const storageService: ObjectStorageService = new S3ObjectStorageService();
