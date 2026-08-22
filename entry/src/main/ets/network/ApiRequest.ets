import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

const TAG = 'ApiRequest';

interface RequestOptions {
  method: http.RequestMethod;
  url: string;
  body?: string;
  apiKey?: string;
  timeoutMs?: number;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  statusCode?: number;
}

interface RequestHeader {
  'Content-Type': string;
  'Accept': string;
  'X-API-Key'?: string;
}

/**
 * Minimal HTTP helper for Syncthing REST requests.
 *
 * It centralizes base URL handling, API-key headers, timeouts, JSON parsing, and
 * error normalization so page code can stay model-oriented.
 */
export class ApiRequest {
  private static baseUrl: string = 'https://localhost:8384';

  static setBaseUrl(url: string): void {
    ApiRequest.baseUrl = url;
  }

  static getBaseUrl(): string {
    return ApiRequest.baseUrl;
  }

  static buildUrl(path: string): string {
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    return `${ApiRequest.baseUrl}${normalizedPath}`;
  }

  private static buildHeaders(apiKey?: string): RequestHeader {
    if (apiKey) {
      const header: RequestHeader = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-API-Key': apiKey
      };
      return header;
    }
    const header: RequestHeader = {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    return header;
  }

  static async executeRequest<T>(options: RequestOptions): Promise<ApiResponse<T>> {
    const httpRequest = http.createHttp();
    const timeout = options.timeoutMs || 30000;

    try {
      const requestOptions: http.HttpRequestOptions = {
        method: options.method,
        header: ApiRequest.buildHeaders(options.apiKey),
        readTimeout: timeout,
        connectTimeout: timeout,
      };

      if (options.body) {
        requestOptions.extraData = options.body;
      }

      const response: http.HttpResponse = await httpRequest.request(options.url, requestOptions);
      const statusCode = response.responseCode;

      Logger.d(TAG, `${options.method} ${options.url} -> ${statusCode}`);

      httpRequest.destroy();

      if (statusCode >= 200 && statusCode < 300) {
        let data: T | undefined = undefined;
        if (typeof response.result === 'string') {
          try {
            data = JSON.parse(response.result as string) as T;
          } catch (parseErr) {
            data = response.result as T;
          }
        } else {
          data = response.result as T;
        }
        return { success: true, data, statusCode };
      } else {
        return {
          success: false,
          error: `HTTP ${statusCode}`,
          statusCode,
        };
      }
    } catch (err) {
      httpRequest.destroy();
      const businessErr = err as BusinessError;
      Logger.e(TAG, `Request failed: ${options.method} ${options.url} - ${businessErr.message}`);
      return {
        success: false,
        error: businessErr.message || 'Network request failed',
        statusCode: 0,
      };
    }
  }

  static async get<T>(
    path: string,
    apiKey?: string,
    timeoutMs?: number
  ): Promise<ApiResponse<T>> {
    const url = ApiRequest.buildUrl(path);
    return ApiRequest.executeRequest<T>({
      method: http.RequestMethod.GET,
      url,
      apiKey,
      timeoutMs,
    });
  }

  static async post<T>(
    path: string,
    body?: Object | string,
    apiKey?: string,
    timeoutMs?: number
  ): Promise<ApiResponse<T>> {
    const url = ApiRequest.buildUrl(path);
    const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);
    return ApiRequest.executeRequest<T>({
      method: http.RequestMethod.POST,
      url,
      body: bodyStr,
      apiKey,
      timeoutMs,
    });
  }

  static async put<T>(
    path: string,
    body?: Object | string,
    apiKey?: string,
    timeoutMs?: number
  ): Promise<ApiResponse<T>> {
    const url = ApiRequest.buildUrl(path);
    const bodyStr = typeof body === 'string' ? body : JSON.stringify(body);
    return ApiRequest.executeRequest<T>({
      method: http.RequestMethod.PUT,
      url,
      body: bodyStr,
      apiKey,
      timeoutMs,
    });
  }

  static async delete<T>(
    path: string,
    apiKey?: string,
    timeoutMs?: number
  ): Promise<ApiResponse<T>> {
    const url = ApiRequest.buildUrl(path);
    return ApiRequest.executeRequest<T>({
      method: http.RequestMethod.DELETE,
      url,
      apiKey,
      timeoutMs,
    });
  }
}
